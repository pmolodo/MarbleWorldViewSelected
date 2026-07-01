using System.Reflection;
using BepInEx;
using UnityEngine;

namespace ViewSelected
{
    /// <summary>
    /// Adds a V hotkey (Ctrl not held) that views the currently selected object: it
    /// moves the camera to look at the object from the game's built-in fixed back-off
    /// distance.
    ///
    /// This is the "simplest" version - it drives the game's existing camera move
    /// (a SmoothDamp toward focusPoint - cameraForward * 5f). Rather than calling
    /// CameraController.CenterOnPoint(), which no-ops unless the in-game "camera
    /// follow build" setting is on, it arms CenterOnPoint's private fields directly
    /// so the hotkey works regardless of that setting. A future version could
    /// compute the distance from the object's bounding-box size + camera FOV instead.
    /// </summary>
    [BepInPlugin(PluginGuid, PluginName, PluginVersion)]
    public class ViewSelectedPlugin : BaseUnityPlugin
    {
        public const string PluginGuid = "com.paulm.marbleworld.viewselected";
        public const string PluginName = "View Selected";
        public const string PluginVersion = "1.0.0";

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

        // The fixed back-off distance CenterOnPoint uses: focusPoint - cameraForward * 5f.
        private const float CameraPullback = 5f;

        private void Awake()
        {
            Logger.LogInfo(
                $"{PluginName} v{PluginVersion} loaded. Press {ViewKey} to view the selected object.");

            if (IsDoingTextInputField == null || ShouldTakeInputField == null)
            {
                Logger.LogWarning(
                    "View Selected: could not resolve MWInputManager input-state fields by " +
                    "reflection (game updated?). The text-input guard is disabled; V will " +
                    "still view the selection.");
            }

            if (FocusObjectPositionField == null || IsMovingToCenterField == null)
            {
                Logger.LogWarning(
                    "View Selected: could not resolve CameraController move fields by reflection " +
                    "(game updated?). Falling back to CenterOnPoint, which is gated on the in-game " +
                    "'camera follow build' setting.");
            }
        }

        private void Update()
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
        /// Returns the center of the selected object's combined renderer bounds,
        /// falling back to its transform position if it has no renderers.
        /// </summary>
        private static Vector3 GetFocusPoint(Selectable selected)
        {
            Renderer[] renderers = selected.GetComponentsInChildren<Renderer>();
            if (renderers == null || renderers.Length == 0)
            {
                return selected.transform.position;
            }

            Bounds bounds = renderers[0].bounds;
            for (int i = 1; i < renderers.Length; i++)
            {
                bounds.Encapsulate(renderers[i].bounds);
            }
            return bounds.center;
        }
    }
}
