enum UberShaderKind {
    Normal = 0,
    Flat = 1,
    Overlay = 2,
    OverlayCorrect = 3,
    WindowFill = 4,
    Animal = 5,
    PaletteSwap = 6,
    PlayerFinal = 7,
    Premultiply = 8,
    Light = 9,
    AnchorSprite = 10,
    AnchorText = 11,
}

function gpu_reset_extra() {
    gpu_set_extra(UberShaderKind.Normal);
}
