#include "ThemeManager.h"
#include <QFile>
#include <QTextStream>
#include <QDir>
#include <QStandardPaths>
#include <QSettings>
#include <QDebug>

ThemeManager::ThemeManager(QObject *parent) : QObject(parent) {
    m_watcher = new QFileSystemWatcher(this);
    QString path = getScssPath();
    if (!path.isEmpty() && QFile::exists(path)) {
        m_watcher->addPath(path);
        connect(m_watcher, &QFileSystemWatcher::fileChanged, this, &ThemeManager::refreshTheme);
    }
    QSettings s;
    m_themeMode = s.value("themeMode", 0).toInt();
    m_dynamicColor = s.value("dynamicColor", true).toBool();
    refreshTheme();
}

void ThemeManager::setThemeMode(int mode) {
    if (m_themeMode == mode) return;
    m_themeMode = mode;
    QSettings s;
    s.setValue("themeMode", mode);
    emit themeModeChanged();
    refreshTheme();
}

void ThemeManager::setDynamicColor(bool dynamic) {
    if (m_dynamicColor == dynamic) return;
    m_dynamicColor = dynamic;
    QSettings s;
    s.setValue("dynamicColor", dynamic);
    emit dynamicColorChanged();
    refreshTheme();
}

QString ThemeManager::getScssPath() const {
    QString xdgState = qgetenv("XDG_STATE_HOME");
    if (xdgState.isEmpty()) {
        xdgState = QDir::homePath() + "/.local/state";
    }
    return xdgState + "/quickshell/user/generated/material_colors.scss";
}

void ThemeManager::refreshTheme() {
    bool parsed = false;
    if (m_dynamicColor) {
        QString path = getScssPath();
        if (QFile::exists(path)) {
            parseScss();
            parsed = true;
        }
    }
    
    if (!parsed) {
        loadHardcoded(m_themeMode);
    }
    
    emit themeChanged();
}

void ThemeManager::loadHardcoded(int mode) {
    if (mode == 1) { // Light
        m_colors.clear();
        m_colors["primary"]                 = "#6750A4";
        m_colors["onPrimary"]               = "#FFFFFF";
        m_colors["primaryContainer"]        = "#EADDFF";
        m_colors["onPrimaryContainer"]      = "#21005D";
        m_colors["secondary"]               = "#625B71";
        m_colors["onSecondary"]             = "#FFFFFF";
        m_colors["secondaryContainer"]      = "#E8DEF8";
        m_colors["onSecondaryContainer"]    = "#1D192B";
        m_colors["error"]                   = "#B3261E";
        m_colors["onError"]                 = "#FFFFFF";
        m_colors["errorContainer"]          = "#F9DEDC";
        m_colors["onErrorContainer"]        = "#410E0B";
        m_colors["surface"]                 = "#FEF7FF";
        m_colors["surfaceDim"]              = "#DED8E1";
        m_colors["surfaceBright"]           = "#FEF7FF";
        m_colors["surfaceContainerLowest"]  = "#FFFFFF";
        m_colors["surfaceContainerLow"]     = "#F7F2FA";
        m_colors["surfaceContainer"]        = "#F3EDF7";
        m_colors["surfaceContainerHigh"]    = "#ECE6F0";
        m_colors["surfaceContainerHighest"] = "#E6E0E9";
        m_colors["onSurface"]               = "#1D1B20";
        m_colors["onSurfaceVariant"]        = "#49454F";
        m_colors["outline"]                 = "#79747E";
        m_colors["outlineVariant"]          = "#CAC4D0";
        m_colors["inverseSurface"]          = "#322F35";
        m_colors["inverseOnSurface"]        = "#F5EFF7";
        m_colors["inversePrimary"]          = "#D0BCFF";
        return;
    }
    if (m_themeMode == 2) { // Dark
        m_colors.clear();
        m_colors["primary"]                 = "#D0BCFF";
        m_colors["onPrimary"]               = "#381E72";
        m_colors["primaryContainer"]        = "#4F378B";
        m_colors["onPrimaryContainer"]      = "#EADDFF";
        m_colors["secondary"]               = "#CCC2DC";
        m_colors["onSecondary"]             = "#332D41";
        m_colors["secondaryContainer"]      = "#4A4458";
        m_colors["onSecondaryContainer"]    = "#E8DEF8";
        m_colors["error"]                   = "#F2B8B5";
        m_colors["onError"]                 = "#601410";
        m_colors["errorContainer"]          = "#8C1D18";
        m_colors["onErrorContainer"]        = "#F9DEDC";
        m_colors["surface"]                 = "#141218";
        m_colors["surfaceDim"]              = "#141218";
        m_colors["surfaceBright"]           = "#3B383E";
        m_colors["surfaceContainerLowest"]  = "#0F0D13";
        m_colors["surfaceContainerLow"]     = "#1D1B20";
        m_colors["surfaceContainer"]        = "#211F26";
        m_colors["surfaceContainerHigh"]    = "#2B2930";
        m_colors["surfaceContainerHighest"] = "#36343B";
        m_colors["onSurface"]               = "#E6E1E5";
        m_colors["onSurfaceVariant"]        = "#CAC4D0";
        m_colors["outline"]                 = "#938F99";
        m_colors["outlineVariant"]          = "#49454F";
        m_colors["inverseSurface"]          = "#E6E1E5";
        m_colors["inverseOnSurface"]        = "#322F35";
        m_colors["inversePrimary"]          = "#6750A4";
        return;
    }
    // System (mode 0) fallback if not using dynamic colors
    if (mode == 0) {
        loadHardcoded(2); // Fallback to Dark
    }
}

void ThemeManager::parseScss() {
    QString path = getScssPath();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "Could not open SCSS file for theming:" << path;
        loadHardcoded(m_themeMode);
        return;
    }
    
    m_colors.clear();

    QTextStream in(&file);
    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.startsWith("$") && line.contains(":")) {
            QStringList parts = line.split(":");
            if (parts.size() >= 2) {
                QString key = parts[0].trimmed();
                QString value = parts[1].split(";")[0].trimmed();
                m_colors[key] = value;
                
                // Also store without $ for easier lookup if needed
                QString baseKey = key.mid(1);
                m_colors[baseKey] = value;
                
                // Handle kebab-case and snake_case to camelCase conversion
                QString camelKey = baseKey;
                while (camelKey.contains("-") || camelKey.contains("_")) {
                    int idx = camelKey.indexOf("-");
                    if (idx == -1) idx = camelKey.indexOf("_");
                    
                    if (idx + 1 < camelKey.length()) {
                        camelKey.replace(idx, 2, camelKey.at(idx+1).toUpper());
                    } else {
                        camelKey.remove(idx, 1);
                    }
                }
                m_colors[camelKey] = value;
            }
        }
    }
    file.close();
    
    // The "Pinkish" Accent Fix logic
    // Prefer inversePrimary over primary in dark mode (assuming dynamic color file specifies it)
    if (m_colors.contains("darkmode") && m_colors["darkmode"] == "true") {
        if (m_colors.contains("inversePrimary")) {
            m_colors["primary"] = m_colors["inversePrimary"];
        }
    } else if (!m_colors.contains("darkmode")) {
        // If we can't explicitly tell, but we have an inversePrimary, maybe we can use it?
        // Wait, only apply the pinkish fix if we actually parsed inversePrimary.
        // Usually inversePrimary in dark mode is brighter/truer to the hue.
        if (m_colors.contains("inversePrimary")) {
            m_colors["primary"] = m_colors["inversePrimary"];
        }
    }
}

#define GET_COLOR(name, fallback) \
QColor ThemeManager::name() const { \
    QString col = m_colors.value("$" #name, m_colors.value(#name, fallback)).toString(); \
    return QColor(col); \
}

GET_COLOR(primary, "#6750A4")
GET_COLOR(onPrimary, "#FFFFFF")
GET_COLOR(primaryContainer, "#EADDFF")
GET_COLOR(onPrimaryContainer, "#21005D")
GET_COLOR(secondary, "#625B71")
GET_COLOR(onSecondary, "#FFFFFF")
GET_COLOR(secondaryContainer, "#E8DEF8")
GET_COLOR(onSecondaryContainer, "#1D192B")
GET_COLOR(tertiary, "#7D5260")
GET_COLOR(onTertiary, "#FFFFFF")
GET_COLOR(tertiaryContainer, "#FFD8E4")
GET_COLOR(onTertiaryContainer, "#31111D")
GET_COLOR(error, "#B3261E")
GET_COLOR(onError, "#FFFFFF")
GET_COLOR(errorContainer, "#F9DEDC")
GET_COLOR(onErrorContainer, "#410E0B")
GET_COLOR(surface, "#FEF7FF")
GET_COLOR(surfaceDim, "#DED8E1")
GET_COLOR(surfaceBright, "#FEF7FF")
GET_COLOR(surfaceContainerLowest, "#FFFFFF")
GET_COLOR(surfaceContainerLow, "#F7F2FA")
GET_COLOR(surfaceContainer, "#F3EDF7")
GET_COLOR(surfaceContainerHigh, "#ECE6F0")
GET_COLOR(surfaceContainerHighest, "#E6E0E9")
GET_COLOR(onSurface, "#1D1B20")
GET_COLOR(onSurfaceVariant, "#49454F")
GET_COLOR(outline, "#79747E")
GET_COLOR(outlineVariant, "#CAC4D0")
GET_COLOR(inverseSurface, "#322F35")
GET_COLOR(inverseOnSurface, "#F5EFF7")
GET_COLOR(inversePrimary, "#D0BCFF")

bool ThemeManager::isDark() const {
    return isColorDark(surface());
}

bool ThemeManager::isColorDark(const QColor &color) const {
    double yiq = ((color.red() * 299) + (color.green() * 587) + (color.blue() * 114)) / 1000.0;
    return yiq < 128.0;
}
