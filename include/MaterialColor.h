#pragma once
#include <QColor>
#include <QHash>
#include <QString>

// A compact port of Google's Material Color Utilities (the library behind
// Android's dynamic colour and matugen): the HCT colour space, tonal
// palettes, and the Material 3 scheme variants. Given a seed colour it
// produces every colour role for light or dark mode.
namespace MaterialColor {

enum class Variant {
    TonalSpot = 0,   // Android's default: calm, seed-led
    Neutral,         // almost greyscale
    Vibrant,         // maximum colourfulness
    Expressive,      // playful, hues shifted away from the seed
    Fidelity,        // keeps the seed colour exactly
    Content,         // like fidelity, made for images
    Rainbow,         // colourful accents on neutral surfaces
    FruitSalad,      // bold, hue-rotated
    Monochrome,      // pure greys
    Count
};

// Every Material 3 role (primary, onPrimary, … surfaceContainerHighest,
// outline, inversePrimary …) keyed by its camelCase name, as "#rrggbb".
QHash<QString, QString> scheme(const QColor &seed, Variant variant, bool dark);

// The Material 3 name of a variant for settings ("Tonal spot", …).
QString variantName(Variant v);

} // namespace MaterialColor
