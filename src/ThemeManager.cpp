#include "ThemeManager.h"
#include <QFile>
#include <QTextStream>
#include <QDir>
#include <QStandardPaths>
#include <QDebug>

ThemeManager::ThemeManager(QObject *parent) : QObject(parent) {
    m_watcher = new QFileSystemWatcher(this);
    QString path = getScssPath();
    if (!path.isEmpty() && QFile::exists(path)) {
        m_watcher->addPath(path);
        connect(m_watcher, &QFileSystemWatcher::fileChanged, this, &ThemeManager::refreshTheme);
    }
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
    parseScss();
    emit themeChanged();
}

void ThemeManager::parseScss() {
    QString path = getScssPath();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "Could not open SCSS file for theming:" << path;
        return;
    }

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
                m_colors[key.mid(1)] = value;
                
                // Handle kebab-case to camelCase conversion for M3 names if they come in kebab
                // e.g. $surface-container -> surfaceContainer
                QString camelKey = key.mid(1);
                while (camelKey.contains("-")) {
                    int idx = camelKey.indexOf("-");
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
