# Ember
yesterday

Update README.md
Ember is a powerful and highly optimized 2D particle system for Roblox, built to simulate ParticleEmitter behavior within GUI elements.

# Features
- **Particle Emitter wrapping**: Uses the ParticleEmitter instance as base for the object, meaning you can use it to determine where to emit and change its properties through the instance itself.
- **Flipbook Support**: Allows the usage of flipbook particles, provided the dimensions of the image (accessiable through `Ember.FlipbookDimensions`).
- **Dynamic Emission Controls**:
  - Emit at a fixed position
  - Emit randomly within a GUI parent
- **Replicates Particle Behavior**: Supports all properties that particle emitters have with a few changes due to the translation from 3D to 2D
- **Highly Efficient**: Applies different tricks to cut down the rendering times (mentioned bellow).

## Optimized for Performance
Ember is built with performance in mind:
- Uses a single `ScreenGui` which is constantly being enabled and disabled to batch-render particles without needing to update the GUI descendants.
- Avoids unnecessary instance creation using particle pooling.
- Caches the properties of the ParticleEmitter through tables to speed up indexing
- Automatically adapts particle emission rates depending on the user’s quality settings, making it scalable across all devices—from low-end phones to high-end PCs.

## Usage

```lua
local Ember = require(path.to.Ember)

local uiEmitter = Ember.new(particleEmitter, UDim2.fromScale(0.5, 0.5))

uiEmitter:EmitInParent(15, guiFrame) -- Emit 15 particles randomly inside a Frame
uiEmitter:EmitAtPosition(10, UDim2.fromScale(0.25, 0.75)) -- Emit at a custom position
uiEmitter:Emit(20) -- Emit 20 particles at default position or inside a parent, depending on the parent of the particleEmitter.

uiEmitter:Clear() -- Removes all active particles
uiEmitter:Destroy() -- Clean up the emitter
```

## Flipbook usage
If you're using flipbook animations, make sure to set the `FlipbookDimensions` (`1024`, `512`, `256`, `128`, `64`, `32`, `16`, `8`) based on your sprite sheet size:

```lua
uiEmitter.FlipbookDimensions = Ember.FlipbookDimensions.By512x512
```

Default dimensions are 1024x1024, if you forget to set it up ember will automatically notify you that you need to set up the dimensions.

# Installation

1. Drop `Ember.lua` into your project.
2. Require it in your client scripts.
3. Create 2D emitter through the `Ember.new()` function.
4. Either use the provided objects method to emit or use the Enabled property of the ParticleEmitter to emit constantly

## Compatibility

- **Client-side only**
yesterday

Update README.md
- Works with all Roblox-supported platforms: PC, mobile, console and VR
yesterday

Update README.md
- Does not require any third-party libraries

## License

None