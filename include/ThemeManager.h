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

    Q_PROPERTY(bool isDark READ isDark NOTIFY themeChanged)
    Q_PROPERTY(int themeMode READ themeMode WRITE setThemeMode NOTIFY themeModeChanged)

public:
    explicit ThemeManager(QObject *parent = nullptr);

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

    int themeMode() const { return m_themeMode; }
    Q_INVOKABLE void setThemeMode(int mode);
    Q_INVOKABLE void refreshTheme();

signals:
    void themeChanged();
    void themeModeChanged();

private:
    void parseScss();
    QString getScssPath() const;

    QVariantMap m_colors;
    QFileSystemWatcher *m_watcher;
    int m_themeMode = 0; // 0=system, 1=light, 2=dark
};
