using BepInEx;
using UnityEngine;

namespace ViewSelected
{
    /// <summary>
    /// Adds a V hotkey (Ctrl not held) that views the currently selected object: it
    /// moves the camera to look at the object from the game's built-in fixed back-off
    /// distance.
    ///
    /// This is the "simplest" version - it reuses the game's existing
    /// CameraController.CenterOnPoint(), which damps the camera to
    /// (focusPoint - cameraForward * 5f). A future version could compute the
    /// distance from the object's bounding-box size + camera FOV instead.
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

        private void Awake()
        {
            Logger.LogInfo(
                $"{PluginName} v{PluginVersion} loaded. Press {ViewKey} to view the selected object.");
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

            TryViewSelected();
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
            camera.CenterOnPoint(focusPoint);
            Logger.LogInfo(
                $"View Selected: viewing '{selected.name}' at {focusPoint}. If the camera does not " +
                "move, check the in-game 'camera follow build' setting - CenterOnPoint is gated on " +
                "GameplaySettings.cameraFollowBuild != 0.");
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
