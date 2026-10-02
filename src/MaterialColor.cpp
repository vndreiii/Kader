#include "MaterialColor.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <optional>

// Port of the parts of Material Color Utilities (Apache-2.0, Google) needed
// to build a Material 3 scheme from a seed colour: CAM16 with the default
// viewing conditions, HCT (hue, chroma, tone) solving, tonal palettes and the
// scheme variants' palette recipes and role tones.

namespace MaterialColor {
namespace {

constexpr double kPi = 3.14159265358979323846;

double sanitizeDeg(double d) {
    d = std::fmod(d, 360.0);
    return d < 0 ? d + 360.0 : d;
}
double toRad(double d) { return d * kPi / 180.0; }
double toDeg(double r) { return r * 180.0 / kPi; }
double signum(double x) { return x < 0 ? -1.0 : (x > 0 ? 1.0 : 0.0); }

// ── sRGB / XYZ / L* ──────────────────────────────────────────────────────
double linearized(int c8) {
    const double n = c8 / 255.0;
    return (n <= 0.040449936 ? n / 12.92 : std::pow((n + 0.055) / 1.055, 2.4)) * 100.0;
}
int delinearized(double lin) {
    const double n = lin / 100.0;
    const double d = n <= 0.0031308 ? n * 12.92 : 1.055 * std::pow(n, 1.0 / 2.4) - 0.055;
    return std::clamp(int(std::lround(d * 255.0)), 0, 255);
}
struct Rgb { int r, g, b; };

Rgb rgbFromXyz(double x, double y, double z) {
    const double r = 3.2413774792388685 * x - 1.5376652402851851 * y - 0.49885366846268053 * z;
    const double g = -0.9691452513005321 * x + 1.8758853451067872 * y + 0.04156585530208860 * z;
    const double b = 0.05562093689691305 * x - 0.20395524564742123 * y + 1.0571799111220335 * z;
    return {delinearized(r), delinearized(g), delinearized(b)};
}
double yFromLstar(double l) {
    return l > 8.0 ? std::pow((l + 16.0) / 116.0, 3.0) * 100.0 : l / (24389.0 / 27.0) * 100.0;
}
double lstarFromY(double y) {
    const double yn = y / 100.0;
    return yn <= 216.0 / 24389.0 ? (24389.0 / 27.0) * yn : 116.0 * std::cbrt(yn) - 16.0;
}
double lstarFromRgb(const Rgb &c) {
    const double y = 0.2126 * linearized(c.r) + 0.7152 * linearized(c.g) + 0.0722 * linearized(c.b);
    return lstarFromY(y);
}
Rgb rgbFromLstar(double l) {
    const int v = delinearized(yFromLstar(l));
    return {v, v, v};
}

// ── CAM16, default viewing conditions (sRGB, D65, average surround) ──────
struct Vc {
    double n, aw, nbb, ncb, c, nc, fl, fLRoot, z;
    std::array<double, 3> rgbD;
};
const Vc &vc() {
    static const Vc v = [] {
        const double wx = 95.047, wy = 100.0, wz = 108.883;
        const double adaptingLuminance = (200.0 / kPi) * yFromLstar(50.0) / 100.0;
        const double rW = wx * 0.401288 + wy * 0.650173 + wz * -0.051461;
        const double gW = wx * -0.250268 + wy * 1.204414 + wz * 0.045854;
        const double bW = wx * -0.002079 + wy * 0.048952 + wz * 0.953127;
        const double f = 0.8 + 2.0 / 10.0;              // surround = 2
        const double c = 0.59 + (0.69 - 0.59) * ((f - 0.9) * 10.0);
        double d = f * (1.0 - (1.0 / 3.6) * std::exp((-adaptingLuminance - 42.0) / 92.0));
        d = std::clamp(d, 0.0, 1.0);
        Vc out;
        out.nc = f;
        out.c = c;
        out.rgbD = {d * (100.0 / rW) + 1.0 - d, d * (100.0 / gW) + 1.0 - d, d * (100.0 / bW) + 1.0 - d};
        const double k = 1.0 / (5.0 * adaptingLuminance + 1.0);
        const double k4 = k * k * k * k;
        const double k4F = 1.0 - k4;
        out.fl = k4 * adaptingLuminance + 0.1 * k4F * k4F * std::cbrt(5.0 * adaptingLuminance);
        out.n = yFromLstar(50.0) / wy;
        out.z = 1.48 + std::sqrt(out.n);
        out.nbb = 0.725 / std::pow(out.n, 0.2);
        out.ncb = out.nbb;
        const double rAF = std::pow(out.fl * out.rgbD[0] * rW / 100.0, 0.42);
        const double gAF = std::pow(out.fl * out.rgbD[1] * gW / 100.0, 0.42);
        const double bAF = std::pow(out.fl * out.rgbD[2] * bW / 100.0, 0.42);
        const double rA = 400.0 * rAF / (rAF + 27.13);
        const double gA = 400.0 * gAF / (gAF + 27.13);
        const double bA = 400.0 * bAF / (bAF + 27.13);
        out.aw = (2.0 * rA + gA + 0.05 * bA) * out.nbb;
        out.fLRoot = std::pow(out.fl, 0.25);
        return out;
    }();
    return v;
}

struct Cam {
    double hue, chroma, j, jstar, astar, bstar;
};

Cam camFromRgb(const Rgb &c) {
    const Vc &v = vc();
    const double r = linearized(c.r), g = linearized(c.g), b = linearized(c.b);
    const double x = 0.41233895 * r + 0.35762064 * g + 0.18051042 * b;
    const double y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    const double z = 0.01932141 * r + 0.11916382 * g + 0.95034478 * b;
    const double rC = 0.401288 * x + 0.650173 * y - 0.051461 * z;
    const double gC = -0.250268 * x + 1.204414 * y + 0.045854 * z;
    const double bC = -0.002079 * x + 0.048952 * y + 0.953127 * z;
    const double rD = v.rgbD[0] * rC, gD = v.rgbD[1] * gC, bD = v.rgbD[2] * bC;
    auto adapt = [&](double d) {
        const double af = std::pow(v.fl * std::abs(d) / 100.0, 0.42);
        return signum(d) * 400.0 * af / (af + 27.13);
    };
    const double rA = adapt(rD), gA = adapt(gD), bA = adapt(bD);
    const double a = (11.0 * rA - 12.0 * gA + bA) / 11.0;
    const double bb = (rA + gA - 2.0 * bA) / 9.0;
    const double u = (20.0 * rA + 20.0 * gA + 21.0 * bA) / 20.0;
    const double p2 = (40.0 * rA + 20.0 * gA + bA) / 20.0;
    const double hue = sanitizeDeg(toDeg(std::atan2(bb, a)));
    const double ac = p2 * v.nbb;
    const double j = 100.0 * std::pow(ac / v.aw, v.c * v.z);
    const double huePrime = hue < 20.14 ? hue + 360.0 : hue;
    const double eHue = 0.25 * (std::cos(toRad(huePrime) + 2.0) + 3.8);
    const double p1 = 50000.0 / 13.0 * eHue * v.nc * v.ncb;
    const double t = p1 * std::hypot(a, bb) / (u + 0.305);
    const double alpha = std::pow(1.64 - std::pow(0.29, v.n), 0.73) * std::pow(t, 0.9);
    const double chroma = alpha * std::sqrt(j / 100.0);
    const double m = chroma * v.fLRoot;
    const double mstar = 1.0 / 0.0228 * std::log1p(0.0228 * m);
    return {hue, chroma, j, (1.0 + 100.0 * 0.007) * j / (1.0 + 0.007 * j),
            mstar * std::cos(toRad(hue)), mstar * std::sin(toRad(hue))};
}

Cam camFromJch(double j, double chroma, double hue) {
    const Vc &v = vc();
    const double m = chroma * v.fLRoot;
    const double mstar = 1.0 / 0.0228 * std::log1p(0.0228 * m);
    return {hue, chroma, j, (1.0 + 100.0 * 0.007) * j / (1.0 + 0.007 * j),
            mstar * std::cos(toRad(hue)), mstar * std::sin(toRad(hue))};
}

Rgb rgbFromCam(const Cam &cam) {
    const Vc &v = vc();
    const double alpha = (cam.chroma == 0.0 || cam.j == 0.0) ? 0.0 : cam.chroma / std::sqrt(cam.j / 100.0);
    const double t = std::pow(alpha / std::pow(1.64 - std::pow(0.29, v.n), 0.73), 1.0 / 0.9);
    const double hRad = toRad(cam.hue);
    const double eHue = 0.25 * (std::cos(hRad + 2.0) + 3.8);
    const double ac = v.aw * std::pow(cam.j / 100.0, 1.0 / v.c / v.z);
    const double p1 = eHue * (50000.0 / 13.0) * v.nc * v.ncb;
    const double p2 = ac / v.nbb;
    const double hSin = std::sin(hRad), hCos = std::cos(hRad);
    const double gamma = 23.0 * (p2 + 0.305) * t / (23.0 * p1 + 11.0 * t * hCos + 108.0 * t * hSin);
    const double a = gamma * hCos, b = gamma * hSin;
    const double rA = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0;
    const double gA = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0;
    const double bA = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0;
    auto unadapt = [&](double x) {
        const double base = std::max(0.0, 27.13 * std::abs(x) / (400.0 - std::abs(x)));
        return signum(x) * (100.0 / v.fl) * std::pow(base, 1.0 / 0.42);
    };
    const double rF = unadapt(rA) / v.rgbD[0];
    const double gF = unadapt(gA) / v.rgbD[1];
    const double bF = unadapt(bA) / v.rgbD[2];
    const double x = 1.86206786 * rF - 1.01125463 * gF + 0.14918677 * bF;
    const double y = 0.38752654 * rF + 0.62144744 * gF - 0.00897398 * bF;
    const double z = -0.01584150 * rF - 0.03412294 * gF + 1.04996444 * bF;
    return rgbFromXyz(x, y, z);
}

double camDistance(const Cam &a, const Cam &b) {
    const double dJ = a.jstar - b.jstar, dA = a.astar - b.astar, dB = a.bstar - b.bstar;
    return 1.41 * std::pow(std::sqrt(dJ * dJ + dA * dA + dB * dB), 0.63);
}

// ── HCT solving (iterative: search J for the tone, then the chroma) ──────
std::optional<Cam> findCamByJ(double hue, double chroma, double tone) {
    double low = 0.0, high = 100.0, bestDl = 1000.0, bestDe = 1000.0;
    std::optional<Cam> best;
    while (std::abs(low - high) > 0.01) {
        const double mid = low + (high - low) / 2.0;
        const Rgb clipped = rgbFromCam(camFromJch(mid, chroma, hue));
        const double clippedL = lstarFromRgb(clipped);
        const double dL = std::abs(tone - clippedL);
        if (dL < 0.2) {
            const Cam camClipped = camFromRgb(clipped);
            const double dE = camDistance(camClipped, camFromJch(camClipped.j, camClipped.chroma, hue));
            if (dE <= 1.0 && dE <= bestDe) {
                bestDl = dL;
                bestDe = dE;
                best = camClipped;
            }
        }
        if (bestDl == 0.0 && bestDe == 0.0)
            break;
        if (clippedL < tone) low = mid; else high = mid;
    }
    return best;
}

Rgb solveHct(double hue, double chroma, double tone) {
    if (chroma < 1.0 || std::round(tone) <= 0.0 || std::round(tone) >= 100.0)
        return rgbFromLstar(tone);
    hue = sanitizeDeg(hue);
    double high = chroma, mid = chroma, low = 0.0;
    bool first = true;
    std::optional<Cam> answer;
    while (std::abs(low - high) >= 0.4) {
        const std::optional<Cam> possible = findCamByJ(hue, mid, tone);
        if (first) {
            if (possible)
                return rgbFromCam(*possible);
            first = false;
            mid = low + (high - low) / 2.0;
            continue;
        }
        if (!possible) {
            high = mid;
        } else {
            answer = possible;
            low = mid;
        }
        mid = low + (high - low) / 2.0;
    }
    return answer ? rgbFromCam(*answer) : rgbFromLstar(tone);
}

struct Palette {
    double hue, chroma;
    QString tone(double t) const {
        const Rgb c = solveHct(hue, chroma, t);
        return QColor(c.r, c.g, c.b).name();
    }
};

// Hue rotation tables (Material's Vibrant / Expressive recipes): the rotation
// for the seed hue's band.
double rotate(double hue, const std::array<double, 9> &hues, const std::array<double, 9> &rotations) {
    for (int i = 0; i < 8; ++i)
        if (hue >= hues[i] && hue < hues[i + 1])
            return sanitizeDeg(hue + rotations[i]);
    return hue;
}

// Material's "temperature" complement, approximated in CAM16 hue: warm and
// cool poles sit near 50° and 230°, so the complement mirrors across them.
double complementHue(double hue) { return sanitizeDeg(hue + 180.0); }

} // namespace

QString variantName(Variant v) {
    switch (v) {
    case Variant::TonalSpot:  return QStringLiteral("Tonal spot");
    case Variant::Neutral:    return QStringLiteral("Neutral");
    case Variant::Vibrant:    return QStringLiteral("Vibrant");
    case Variant::Expressive: return QStringLiteral("Expressive");
    case Variant::Fidelity:   return QStringLiteral("Fidelity");
    case Variant::Content:    return QStringLiteral("Content");
    case Variant::Rainbow:    return QStringLiteral("Rainbow");
    case Variant::FruitSalad: return QStringLiteral("Fruit salad");
    case Variant::Monochrome: return QStringLiteral("Monochrome");
    default:                  return QString();
    }
}

QHash<QString, QString> scheme(const QColor &seed, Variant variant, bool dark) {
    const Cam src = camFromRgb({seed.red(), seed.green(), seed.blue()});
    const double h = src.hue, c = src.chroma;

    Palette p{h, 36}, s{h, 16}, t{sanitizeDeg(h + 60), 24}, n{h, 6}, nv{h, 8};
    switch (variant) {
    case Variant::TonalSpot:
        break;
    case Variant::Neutral:
        p = {h, 12}; s = {h, 8}; t = {h, 16}; n = {h, 2}; nv = {h, 2};
        break;
    case Variant::Vibrant:
        p = {h, 200};
        s = {rotate(h, {0, 41, 61, 101, 131, 181, 251, 301, 360}, {18, 15, 10, 12, 15, 18, 15, 12, 12}), 24};
        t = {rotate(h, {0, 41, 61, 101, 131, 181, 251, 301, 360}, {35, 30, 20, 25, 30, 35, 30, 25, 25}), 32};
        n = {h, 10}; nv = {h, 12};
        break;
    case Variant::Expressive:
        p = {sanitizeDeg(h + 240), 40};
        s = {rotate(h, {0, 21, 51, 121, 151, 191, 271, 321, 360}, {45, 95, 45, 20, 45, 90, 45, 45, 45}), 24};
        t = {rotate(h, {0, 21, 51, 121, 151, 191, 271, 321, 360}, {120, 120, 20, 45, 20, 15, 20, 120, 120}), 32};
        n = {sanitizeDeg(h + 15), 8}; nv = {sanitizeDeg(h + 15), 12};
        break;
    case Variant::Fidelity:
        p = {h, c};
        s = {h, std::max(c - 32.0, c * 0.5)};
        t = {complementHue(h), std::max(c - 32.0, c * 0.5)};
        n = {h, c / 8.0}; nv = {h, c / 8.0 + 4.0};
        break;
    case Variant::Content:
        p = {h, c};
        s = {h, std::max(c - 32.0, c * 0.5)};
        t = {sanitizeDeg(h + 60), std::max(c - 32.0, c * 0.5)};
        n = {h, c / 8.0}; nv = {h, c / 8.0 + 4.0};
        break;
    case Variant::Rainbow:
        p = {h, 48}; s = {h, 16}; t = {sanitizeDeg(h + 60), 24}; n = {h, 0}; nv = {h, 0};
        break;
    case Variant::FruitSalad:
        p = {sanitizeDeg(h - 50), 48}; s = {sanitizeDeg(h - 50), 36}; t = {h, 36}; n = {h, 10}; nv = {h, 16};
        break;
    case Variant::Monochrome:
        p = {h, 0}; s = {h, 0}; t = {h, 0}; n = {h, 0}; nv = {h, 0};
        break;
    default:
        break;
    }
    const Palette err{25, 84};
    const bool mono = variant == Variant::Monochrome;

    QHash<QString, QString> o;
    auto role = [&](const char *name, const Palette &pal, double darkTone, double lightTone) {
        o.insert(QString::fromLatin1(name), pal.tone(dark ? darkTone : lightTone));
    };
    if (mono) {
        role("primary", p, 100, 0);           role("onPrimary", p, 10, 90);
        role("primaryContainer", p, 85, 25);  role("onPrimaryContainer", p, 0, 100);
        role("tertiary", t, 90, 25);          role("onTertiary", t, 10, 90);
        role("tertiaryContainer", t, 60, 49); role("onTertiaryContainer", t, 0, 100);
        role("secondaryContainer", s, 30, 85);
    } else {
        role("primary", p, 80, 40);           role("onPrimary", p, 20, 100);
        role("primaryContainer", p, 30, 90);  role("onPrimaryContainer", p, 90, 10);
        role("tertiary", t, 80, 40);          role("onTertiary", t, 20, 100);
        role("tertiaryContainer", t, 30, 90); role("onTertiaryContainer", t, 90, 10);
        role("secondaryContainer", s, 30, 90);
    }
    role("secondary", s, 80, 40);             role("onSecondary", s, 20, 100);
    role("onSecondaryContainer", s, 90, 10);
    role("error", err, 80, 40);               role("onError", err, 20, 100);
    role("errorContainer", err, 30, 90);      role("onErrorContainer", err, 90, 10);
    role("surface", n, 6, 98);                role("surfaceDim", n, 6, 87);
    role("surfaceBright", n, 24, 98);         role("surfaceContainerLowest", n, 4, 100);
    role("surfaceContainerLow", n, 10, 96);   role("surfaceContainer", n, 12, 94);
    role("surfaceContainerHigh", n, 17, 92);  role("surfaceContainerHighest", n, 22, 90);
    role("onSurface", n, 90, 10);             role("onSurfaceVariant", nv, 80, 30);
    role("outline", nv, 60, 50);              role("outlineVariant", nv, 30, 80);
    role("inverseSurface", n, 90, 20);        role("inverseOnSurface", n, 20, 95);
    role("inversePrimary", p, 40, 80);
    return o;
}

} // namespace MaterialColor
