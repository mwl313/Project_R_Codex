# UI Transitions

## Summary

Scene transition is unified to a single wipe system (no overlapping slide scenes).

- `FORWARD`: black band moves right -> left while the new scene is revealed behind it.
- `BACK`: black band moves left -> right while the new scene is revealed behind it.
- During transition, input is blocked.

## API

Preferred API:

```lua
SceneManager:change(sceneName, params, transitionDirection, transitionOpts)
```

Compatibility API (legacy callsite support):

```lua
SceneManager:setScene(sceneName, params, transitionDirection, transitionOpts)
```

Parameters:

- `sceneName`: target scene key
- `params`: `enter(params)` payload
- `transitionDirection`: optional
  - `Config.TRANSITION_FORWARD` (`"FORWARD"`)
  - `Config.TRANSITION_BACK` (`"BACK"`)
- `transitionOpts` (optional)
  - `durationSec`
  - `bandWidthRatio`
  - `edgeSoftnessPx`

If `transitionDirection` is `nil`, behavior remains immediate scene switch (no animation).

## Implementation Detail

- Module: `managers/transition_manager.lua`
- Method: transition start captures `fromScene` and `toScene` each once into 1280x720 canvases.
- During animation, only the two snapshots are rendered.
- Scene `update/draw` are not re-executed during transition frame-by-frame.

This removes overlap-style transition artifacts and keeps wipe visually deterministic.

## Configuration

Defined in `config.lua`:

- `TRANSITION_WIPE_ENABLED = true`
- `TRANSITION_WIPE_DURATION_SEC = 0.80`
- `TRANSITION_WIPE_BAND_WIDTH_RATIO = 1.00`
- `TRANSITION_WIPE_EDGE_SOFTNESS_PX = 24`
- `TRANSITION_FORWARD = "FORWARD"`
- `TRANSITION_BACK = "BACK"`

All transition rendering is world-coordinate based (`1280x720`) and works with `RenderScale`.

## Input Blocking

While transition is active, `app.lua` consumes:

- `mousepressed`
- `mousereleased`
- `keypressed`
- `textinput`
- `textedited`

So buttons and scene input cannot fire during wipe playback.
