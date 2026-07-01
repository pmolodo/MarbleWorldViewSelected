// SPDX-License-Identifier: MIT
using System.Reflection;
using BepInEx;
using UnityEngine;

namespace ViewSelected
{
    /// <summary>
    /// Adds two camera helpers to Marble World's free-fly camera:
    ///
    /// 1. A V hotkey (Ctrl not held) that views the currently selected object -
    ///    it moves the camera to look at the object from the game's built-in fixed
    ///    back-off distance. Rather than calling CameraController.CenterOnPoint(),
    ///    which no-ops unless the in-game "camera follow build" setting is on, it
    ///    arms CenterOnPoint's private fields directly so the hotkey works regardless
    ///    of that setting.
    ///
    /// 2. A middle-mouse drag that orbits the camera (3D-modeler style) around the
    ///    selected object's focus point - or, with nothing selected, around a point
    ///    straight ahead of the camera. When a selection is off-screen the view is
    ///    first snapped to face it, so we never orbit around an off-camera pivot.
    ///
    /// The game's camera is otherwise free-fly / FPS-style (right-mouse look, no
    /// orbit). A future version could compute the view distance from the object's
    /// bounding-box size + camera FOV instead of the fixed back-off.
    /// </summary>
    [BepInPlugin(PluginGuid, PluginName, PluginVersion)]
    public class ViewSelectedPlugin : BaseUnityPlugin
    {
        public const string PluginGuid = "com.paulm.marbleworld.viewselected";
        public const string PluginName = "View Selected";
        public const string PluginVersion = "1.1.0";

        // The key that, while Ctrl is NOT held, views the selection.
        // Plain V is unused in-game (only the game's Ctrl+V = Paste is wired), so it
        // is free to overload - mirroring how the game reuses r for QuickRotate while
        // Ctrl+R is Redo.
        private const KeyCode ViewKey = KeyCode.V;

        // The game tracks input state as private bools on MWInputManager: isDoingTextInput
        // (true while a text field is focused; set by InputFieldHandler on EventSystem
        // select/deselect, and mirrored onto CameraController) and shouldTakeInput (false
        // while input is globally suppressed, e.g. during level loads). MWInputManager.Update
        // skips gameplay input when either gate is active; we read the same fields by
        // reflection so V honors the game's own guard.
        private static readonly FieldInfo IsDoingTextInputField = typeof(MWInputManager).GetField(
            "isDoingTextInput", BindingFlags.NonPublic | BindingFlags.Instance);
        private static readonly FieldInfo ShouldTakeInputField = typeof(MWInputManager).GetField(
            "shouldTakeInput", BindingFlags.NonPublic | BindingFlags.Instance);

        // CenterOnPoint arms these two private fields on CameraController; the game's
        // Update() then SmoothDamps the camera toward focusObjectPosition whenever
        // isMovingToCenterOnObject is true - with no cameraFollowBuild check. We set them
        // directly to bypass CenterOnPoint's GameplaySettings.cameraFollowBuild != 0 gate,
        // so V works regardless of the in-game "camera follow build" setting.
        private static readonly FieldInfo FocusObjectPositionField = typeof(CameraController).GetField(
            "focusObjectPosition", BindingFlags.NonPublic | BindingFlags.Instance);
        private static readonly FieldInfo IsMovingToCenterField = typeof(CameraController).GetField(
            "isMovingToCenterOnObject", BindingFlags.NonPublic | BindingFlags.Instance);

        // The game stores its free-fly look angles in these private fields and, while the
        // right-mouse look key is held, sets transform.eulerAngles from the *Smoothed pair
        // (CameraController.Update). Orbiting moves the camera behind the game's back, so we
        // write our resulting orientation back into these on release - otherwise the next
        // right-mouse look would snap the view to the stale angles.
        private static readonly FieldInfo YawField = typeof(CameraController).GetField(
            "yaw", BindingFlags.NonPublic | BindingFlags.Instance);
        private static readonly FieldInfo PitchField = typeof(CameraController).GetField(
            "pitch", BindingFlags.NonPublic | BindingFlags.Instance);
        private static readonly FieldInfo YawSmoothedField = typeof(CameraController).GetField(
            "yawSmoothed", BindingFlags.NonPublic | BindingFlags.Instance);
        private static readonly FieldInfo PitchSmoothedField = typeof(CameraController).GetField(
            "pitchSmoothed", BindingFlags.NonPublic | BindingFlags.Instance);

        // The fixed back-off distance CenterOnPoint uses: focusPoint - cameraForward * 5f.
        private const float CameraPullback = 5f;

        // Mouse buttons for Unity's legacy Input.GetMouseButton*: middle drives orbit,
        // right is the game's look key (we skip orbit while it is held to avoid a fight).
        private const int MiddleMouseButton = 2;
        private const int RightMouseButton = 1;

        // Orbit tuning. OrbitRotateSpeed mirrors CameraController's serialized rotateSpeed
        // (default 2f) so orbit sensitivity matches the game's look; both are further scaled
        // by GameplaySettings.cameraRotateSpeed. Pitch is clamped short of the poles to avoid
        // flipping over the top. Re-aim only fires when the pivot is more than a hair
        // off-center, so an already-centered selection does not jump.
        private const float OrbitRotateSpeed = 2f;
        private const float OrbitPitchLimitDegrees = 89f;
        private const float OrbitReaimThresholdDegrees = 1f;

        // With nothing selected, orbit around a point this far straight ahead of the camera.
        private const float OrbitFallbackPivotDistance = 5f;

        // Below this the camera sits essentially on the pivot; skip to avoid NaNs.
        private const float PivotEpsilon = 0.0001f;

        // Orbit session state (a middle-mouse drag).
        private bool orbiting;
        private Vector3 orbitPivot;
        private bool savedCursorVisible;
        private CursorLockMode savedCursorLock;

        private void Awake()
        {
            Logger.LogInfo(
                $"{PluginName} v{PluginVersion} loaded. Press {ViewKey} to view the selected " +
                "object; middle-mouse drag to orbit it.");

            if (IsDoingTextInputField == null || ShouldTakeInputField == null)
            {
                Logger.LogWarning(
                    "View Selected: could not resolve MWInputManager input-state fields by " +
                    "reflection (game updated?). The text-input guard is disabled; V and orbit " +
                    "will still work.");
            }

            if (FocusObjectPositionField == null || IsMovingToCenterField == null)
            {
                Logger.LogWarning(
                    "View Selected: could not resolve CameraController move fields by reflection " +
                    "(game updated?). Falling back to CenterOnPoint, which is gated on the in-game " +
                    "'camera follow build' setting.");
            }

            if (YawField == null || PitchField == null || YawSmoothedField == null
                || PitchSmoothedField == null)
            {
                Logger.LogWarning(
                    "View Selected: could not resolve CameraController look-angle fields by " +
                    "reflection (game updated?). Orbit still works, but the next right-mouse look " +
                    "after an orbit may snap the view.");
            }
        }

        private void Update()
        {
            HandleViewHotkey();
            HandleOrbit();
        }

        private void HandleViewHotkey()
        {
            // Cheap early-out: only do work on the frame the view key is pressed.
            if (!Input.GetKeyDown(ViewKey))
            {
                return;
            }

            // Require Ctrl to NOT be held: plain V views the selection, while Ctrl+V
            // is left to the game's Paste command.
            bool ctrlHeld = Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);
            if (ctrlHeld)
            {
                return;
            }

            // Mirror the game's own input gate: don't view while the user is typing in a
            // text field or while input is globally suppressed.
            if (!IsGameAcceptingInput())
            {
                return;
            }

            TryViewSelected();
        }

        /// <summary>
        /// Middle-mouse drag orbits the camera around the selection's focus point (or a
        /// point straight ahead when nothing is selected). Starts on middle-mouse-down,
        /// tracks while held, and ends on release or when input is suppressed.
        /// </summary>
        private void HandleOrbit()
        {
            if (orbiting)
            {
                if (!Input.GetMouseButton(MiddleMouseButton) || !IsGameAcceptingInput())
                {
                    EndOrbit();
                    return;
                }

                UpdateOrbit();
                return;
            }

            if (!Input.GetMouseButtonDown(MiddleMouseButton) || !IsGameAcceptingInput())
            {
                return;
            }

            // Don't start while the game's own right-mouse look is active - that writes
            // transform.eulerAngles every frame and would fight the orbit.
            if (Input.GetMouseButton(RightMouseButton))
            {
                return;
            }

            BeginOrbit();
        }

        private void BeginOrbit()
        {
            CameraController camera = CameraController.instance;
            if (camera == null)
            {
                return;
            }

            Transform cam = camera.transform;
            orbitPivot = GetOrbitPivot(cam);

            // Cancel any in-flight focus (V) move so its SmoothDamp doesn't fight the orbit.
            IsMovingToCenterField?.SetValue(camera, false);

            // If the pivot is off-center (or behind the camera), snap the view to face it
            // first, so we don't orbit around a point that is off-screen. An already-centered
            // pivot is within the threshold and left alone.
            Vector3 toPivot = orbitPivot - cam.position;
            if (toPivot.sqrMagnitude > PivotEpsilon * PivotEpsilon
                && Vector3.Angle(cam.forward, toPivot) > OrbitReaimThresholdDegrees)
            {
                cam.rotation = Quaternion.LookRotation(toPivot, Vector3.up);
            }

            orbiting = true;
            savedCursorVisible = Cursor.visible;
            savedCursorLock = Cursor.lockState;
            Cursor.visible = false;
            Cursor.lockState = CursorLockMode.Locked;
        }

        private void UpdateOrbit()
        {
            CameraController camera = CameraController.instance;
            if (camera == null)
            {
                EndOrbit();
                return;
            }

            Transform cam = camera.transform;
            Vector3 offset = cam.position - orbitPivot;
            float distance = offset.magnitude;
            if (distance < PivotEpsilon)
            {
                return;
            }

            Vector2 mouseDelta = GetMouseDelta();
            float sensitivity = OrbitRotateSpeed * GameplaySettings.cameraRotateSpeed;
            float yawDelta = mouseDelta.x * sensitivity;
            float pitchDelta = mouseDelta.y * sensitivity;
            if (GameplaySettings.cameraYAxisInverted == 1)
            {
                pitchDelta = -pitchDelta;
            }

            // Spherical orbit: azimuth around world up, elevation above the horizontal
            // plane, radius fixed. Elevation is clamped short of the poles.
            float azimuth = Mathf.Atan2(offset.x, offset.z) * Mathf.Rad2Deg + yawDelta;
            float elevation = Mathf.Asin(Mathf.Clamp(offset.y / distance, -1f, 1f)) * Mathf.Rad2Deg;
            elevation = Mathf.Clamp(elevation + pitchDelta, -OrbitPitchLimitDegrees, OrbitPitchLimitDegrees);

            float azimuthRad = azimuth * Mathf.Deg2Rad;
            float elevationRad = elevation * Mathf.Deg2Rad;
            float cosElevation = Mathf.Cos(elevationRad);
            Vector3 direction = new Vector3(
                cosElevation * Mathf.Sin(azimuthRad),
                Mathf.Sin(elevationRad),
                cosElevation * Mathf.Cos(azimuthRad));

            cam.position = orbitPivot + direction * distance;
            cam.rotation = Quaternion.LookRotation(orbitPivot - cam.position, Vector3.up);
        }

        private void EndOrbit()
        {
            orbiting = false;
            Cursor.visible = savedCursorVisible;
            Cursor.lockState = savedCursorLock;
            WriteBackLookAngles();
        }

        /// <summary>
        /// Returns the point to orbit around: the current selection's focus point, or a
        /// point straight ahead of the camera when nothing is selected.
        /// </summary>
        private static Vector3 GetOrbitPivot(Transform cam)
        {
            SelectableManager selection = SelectableManager.instance;
            if (selection != null && selection.GetHasSelectablesSelected())
            {
                Selectable selected = selection.GetFirstSelected();
                if (selected != null)
                {
                    return GetFocusPoint(selected);
                }
            }

            return cam.position + cam.forward * OrbitFallbackPivotDistance;
        }

        /// <summary>
        /// Syncs the game's private look angles to the camera's current orientation so the
        /// next right-mouse look continues smoothly instead of snapping to stale values.
        /// </summary>
        private static void WriteBackLookAngles()
        {
            CameraController camera = CameraController.instance;
            if (camera == null || YawField == null || PitchField == null
                || YawSmoothedField == null || PitchSmoothedField == null)
            {
                return;
            }

            Vector3 euler = camera.transform.eulerAngles;
            PitchField.SetValue(camera, euler.x);
            YawField.SetValue(camera, euler.y);
            PitchSmoothedField.SetValue(camera, euler.x);
            YawSmoothedField.SetValue(camera, euler.y);
        }

        private static Vector2 GetMouseDelta()
        {
            MWInputManager input = MWInputManager.instance;
            return input != null ? input.GetMouseDelta() : Vector2.zero;
        }

        /// <summary>
        /// Mirrors the game's input gate (MWInputManager.Update): returns false while a
        /// text field is focused (isDoingTextInput) or input is globally suppressed
        /// (shouldTakeInput == false). If the private fields could not be resolved, the
        /// guard degrades to "accepting" so the core hotkey keeps working.
        /// </summary>
        private static bool IsGameAcceptingInput()
        {
            MWInputManager input = MWInputManager.instance;
            if (input == null)
            {
                return true;
            }

            if (ShouldTakeInputField != null && !(bool)ShouldTakeInputField.GetValue(input))
            {
                return false;
            }

            if (IsDoingTextInputField != null && (bool)IsDoingTextInputField.GetValue(input))
            {
                return false;
            }

            return true;
        }

        private void TryViewSelected()
        {
            CameraController camera = CameraController.instance;
            if (camera == null)
            {
                Logger.LogWarning("View Selected: no CameraController.instance available.");
                return;
            }

            SelectableManager selection = SelectableManager.instance;
            if (selection == null || !selection.GetHasSelectablesSelected())
            {
                Logger.LogInfo("View Selected: nothing selected.");
                return;
            }

            // GetFirstSelected() indexes _selectedSelectables[0] with no empty-check,
            // so it must only be called after GetHasSelectablesSelected() is true.
            Selectable selected = selection.GetFirstSelected();
            if (selected == null)
            {
                Logger.LogInfo("View Selected: selection was empty.");
                return;
            }

            Vector3 focusPoint = GetFocusPoint(selected);
            CenterOnPointUngated(camera, focusPoint);
            Logger.LogInfo($"View Selected: viewing '{selected.name}' at {focusPoint}.");
        }

        /// <summary>
        /// Moves the camera to frame focusPoint the same way CameraController.CenterOnPoint
        /// does (SmoothDamp toward focusPoint - cameraForward * CameraPullback), but bypasses
        /// its GameplaySettings.cameraFollowBuild != 0 gate by arming the private fields
        /// directly. The move itself (CameraController.Update) is gated only on
        /// isMovingToCenterOnObject, not on the setting. If the fields could not be resolved,
        /// falls back to the public CenterOnPoint (which respects the setting).
        /// </summary>
        private static void CenterOnPointUngated(CameraController camera, Vector3 focusPoint)
        {
            if (FocusObjectPositionField == null || IsMovingToCenterField == null)
            {
                camera.CenterOnPoint(focusPoint);
                return;
            }

            Vector3 target = focusPoint + -camera.transform.forward * CameraPullback;
            FocusObjectPositionField.SetValue(camera, target);
            IsMovingToCenterField.SetValue(camera, true);
        }

        /// <summary>
        /// Returns the point to frame / orbit around: the position of the game's
        /// transform gizmo (TranslateTool). SelectableManager.SetEditToolsLocations parks
        /// the gizmo wherever edits pivot - the centroid of a multi-selection, or the
        /// current snap node when Tab cycles a track's nodes - so it follows what the user
        /// is actually manipulating far better than a single object's transform or its
        /// renderer bounds (which can sit well off the visible object). All three tools
        /// (Translate / Rotate / Scale) are kept co-located, so TranslateTool is
        /// representative regardless of which one is active. Falls back to the first
        /// selected object's position if the gizmo singleton is not yet available.
        /// </summary>
        private static Vector3 GetFocusPoint(Selectable selected)
        {
            TranslateTool gizmo = TranslateTool.instance;
            if (gizmo != null)
            {
                return gizmo.transform.position;
            }

            return selected.transform.position;
        }
    }
}
