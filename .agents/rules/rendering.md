# Rendering rule

Read this before changing `StatusIconRenderer`, `StatusIconGeometry`,
`IconPresentationMapper`, `IconSceneState`, `StatusBarController` icon
rendering, `AppIconController`, `DockIconRenderKey`, `DockIconRenderer`, any
`Sources/**/UI/Icon/**` file, or any rendering/icon test.

- Menu Bar and Dock rendering must stay on the same scene and settings source.
  A menu-bar-only option needs an explicit product decision, documentation, and
  a test.
- Run `bash scripts/test.sh 'Issue30WiFiAlignmentTests|IconSurfaceIntegrationTests'`.
- While iterating, run the focused mapper/renderer filter for the path you
  touched. Run the full local profile on the final integrated tree before
  delivery, because those paths can affect CPU, memory, and both surfaces.
- Visible SF Symbol ink, not the layout-box centre, must land on
  `StatusIconGeometry.artworkCenterX`.

See `docs/issue-30-wifi-centering-analysis.md`,
`docs/api/icon-presentation.md`, and `docs/presentation-state-architecture.md`.
