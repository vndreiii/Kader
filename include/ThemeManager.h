#pragma once

#include <QObject>
#include <QColor>
#include <QVariantMap>
#include <QFileSystemWatcher>

class ThemeManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QColor primary READ primary NOTIFY themeChanged)
    Q_PROPERTY(QColor onPrimary READ onPrimary NOTIFY themeChanged)
    Q_PROPERTY(QColor primaryContainer READ primaryContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor onPrimaryContainer READ onPrimaryContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor secondary READ secondary NOTIFY themeChanged)
    Q_PROPERTY(QColor onSecondary READ onSecondary NOTIFY themeChanged)
    Q_PROPERTY(QColor secondaryContainer READ secondaryContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor onSecondaryContainer READ onSecondaryContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor tertiary READ tertiary NOTIFY themeChanged)
    Q_PROPERTY(QColor onTertiary READ onTertiary NOTIFY themeChanged)
    Q_PROPERTY(QColor tertiaryContainer READ tertiaryContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor onTertiaryContainer READ onTertiaryContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor error READ error NOTIFY themeChanged)
    Q_PROPERTY(QColor onError READ onError NOTIFY themeChanged)
    Q_PROPERTY(QColor errorContainer READ errorContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor onErrorContainer READ onErrorContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor surface READ surface NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceDim READ surfaceDim NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceBright READ surfaceBright NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceContainerLowest READ surfaceContainerLowest NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceContainerLow READ surfaceContainerLow NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceContainer READ surfaceContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceContainerHigh READ surfaceContainerHigh NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceContainerHighest READ surfaceContainerHighest NOTIFY themeChanged)
    Q_PROPERTY(QColor onSurface READ onSurface NOTIFY themeChanged)
    Q_PROPERTY(QColor onSurfaceVariant READ onSurfaceVariant NOTIFY themeChanged)
    Q_PROPERTY(QColor outline READ outline NOTIFY themeChanged)
    Q_PROPERTY(QColor outlineVariant READ outlineVariant NOTIFY themeChanged)
    Q_PROPERTY(QColor inverseSurface READ inverseSurface NOTIFY themeChanged)
    Q_PROPERTY(QColor inverseOnSurface READ inverseOnSurface NOTIFY themeChanged)
    Q_PROPERTY(QColor inversePrimary READ inversePrimary NOTIFY themeChanged)

    // Motion
    Q_PROPERTY(int durShort READ durShort CONSTANT)
    Q_PROPERTY(int durMed READ durMed CONSTANT)
    Q_PROPERTY(int durLong READ durLong CONSTANT)

    // Shape scale
    Q_PROPERTY(int radiusXs READ radiusXs CONSTANT)
    Q_PROPERTY(int radiusSm READ radiusSm CONSTANT)
    Q_PROPERTY(int radiusMd READ radiusMd CONSTANT)
    Q_PROPERTY(int radiusLg READ radiusLg CONSTANT)
    Q_PROPERTY(int radiusXl READ radiusXl CONSTANT)
    Q_PROPERTY(int radiusXxl READ radiusXxl CONSTANT)

    // Type scale
    Q_PROPERTY(int fontLabelS READ fontLabelS CONSTANT)
    Q_PROPERTY(int fontLabelM READ fontLabelM CONSTANT)
    Q_PROPERTY(int fontLabelL READ fontLabelL CONSTANT)
    Q_PROPERTY(int fontBodyM READ fontBodyM CONSTANT)
    Q_PROPERTY(int fontBodyL READ fontBodyL CONSTANT)
    Q_PROPERTY(int fontTitle READ fontTitle CONSTANT)
    Q_PROPERTY(int fontHeadlineS READ fontHeadlineS CONSTANT)
    Q_PROPERTY(int fontHeadlineM READ fontHeadlineM CONSTANT)
    Q_PROPERTY(int fontDisplayS READ fontDisplayS CONSTANT)

    // State layers
    Q_PROPERTY(qreal hoverOpacity READ hoverOpacity CONSTANT)
    Q_PROPERTY(qreal pressOpacity READ pressOpacity CONSTANT)

    Q_PROPERTY(bool isDark READ isDark NOTIFY themeChanged)
    Q_PROPERTY(int themeMode READ themeMode WRITE setThemeMode NOTIFY themeModeChanged)
    // Where the colours come from: 0 Kader's own, 1 a preset colour, 2 the
    // system (matugen, Quickshell, or the desktop accent colour).
    Q_PROPERTY(int colorSource READ colorSource WRITE setColorSource NOTIFY colorSourceChanged)
    Q_PROPERTY(QString seedColor READ seedColor WRITE setSeedColor NOTIFY colorSourceChanged)
    // Material 3 scheme style (MaterialColor::Variant)
    Q_PROPERTY(int schemeVariant READ schemeVariant WRITE setSchemeVariant NOTIFY colorSourceChanged)
    Q_PROPERTY(QStringList presetColors READ presetColors CONSTANT)
    Q_PROPERTY(QStringList variantNames READ variantNames CONSTANT)
    // what "system" colours were found: "matugen", "quickshell", "accent" or ""
    Q_PROPERTY(QString systemSource READ systemSource NOTIFY themeChanged)
    Q_PROPERTY(QString matugenPath READ matugenPath CONSTANT)

public:
    explicit ThemeManager(QObject *parent = nullptr);
    bool eventFilter(QObject *watched, QEvent *event) override;

    bool isDark() const;
    Q_INVOKABLE bool isColorDark(const QColor &color) const;

    QColor primary() const;
    QColor onPrimary() const;
    QColor primaryContainer() const;
    QColor onPrimaryContainer() const;
    QColor secondary() const;
    QColor onSecondary() const;
    QColor secondaryContainer() const;
    QColor onSecondaryContainer() const;
    QColor tertiary() const;
    QColor onTertiary() const;
    QColor tertiaryContainer() const;
    QColor onTertiaryContainer() const;
    QColor error() const;
    QColor onError() const;
    QColor errorContainer() const;
    QColor onErrorContainer() const;
    QColor surface() const;
    QColor surfaceDim() const;
    QColor surfaceBright() const;
    QColor surfaceContainerLowest() const;
    QColor surfaceContainerLow() const;
    QColor surfaceContainer() const;
    QColor surfaceContainerHigh() const;
    QColor surfaceContainerHighest() const;
    QColor onSurface() const;
    QColor onSurfaceVariant() const;
    QColor outline() const;
    QColor outlineVariant() const;
    QColor inverseSurface() const;
    QColor inverseOnSurface() const;
    QColor inversePrimary() const;

    int durShort() const { return 150; }
    int durMed() const { return 300; }
    int durLong() const { return 500; }

    int radiusXs() const { return 4; }
    int radiusSm() const { return 8; }
    int radiusMd() const { return 12; }
    int radiusLg() const { return 16; }
    int radiusXl() const { return 20; }
    int radiusXxl() const { return 28; }

    int fontLabelS() const { return 11; }
    int fontLabelM() const { return 12; }
    int fontLabelL() const { return 14; }
    int fontBodyM() const { return 14; }
    int fontBodyL() const { return 16; }
    int fontTitle() const { return 22; }
    int fontHeadlineS() const { return 24; }
    int fontHeadlineM() const { return 28; }
    int fontDisplayS() const { return 36; }

    qreal hoverOpacity() const { return 0.08; }
    qreal pressOpacity() const { return 0.10; }

    int themeMode() const { return m_themeMode; }
    Q_INVOKABLE void setThemeMode(int mode);
    Q_INVOKABLE void refreshTheme();

    Q_PROPERTY(bool dynamicColor READ dynamicColor WRITE setDynamicColor NOTIFY dynamicColorChanged)
    bool dynamicColor() const { return m_colorSource == 2; }
    Q_INVOKABLE void setDynamicColor(bool dynamic);

    int colorSource() const { return m_colorSource; }
    void setColorSource(int s);
    QString seedColor() const { return m_seed; }
    void setSeedColor(const QString &c);
    int schemeVariant() const { return m_variant; }
    void setSchemeVariant(int v);
    QStringList presetColors() const;
    QStringList variantNames() const;
    QString systemSource() const { return m_systemSource; }
    QString matugenPath() const;

signals:
    void themeChanged();
    void themeModeChanged();
    void dynamicColorChanged();
    void colorSourceChanged();

private:
    QColor systemSeed(bool *darkHint, bool *hasHint);
    void watchFiles();
    static bool systemIsLight();

    QVariantMap m_colors;
    QFileSystemWatcher *m_watcher;
    int m_themeMode = 0; // 0=system, 1=light, 2=dark
    int m_colorSource = 0;
    QString m_seed = QStringLiteral("#6750A4");
    int m_variant = 0;
    QString m_systemSource;
};
