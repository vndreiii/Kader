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
        // Set some dark mode defaults
        m_colors["$background"] = "#1a1c1e";
        m_colors["$onSurface"] = "#e2e2e6";
        m_colors["$primary"] = "#d1e1ff";
        m_colors["$surfaceContainer"] = "#1e1f22";
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
            }
        }
    }
    file.close();
}

QColor ThemeManager::primaryColor() const {
    // Prefer inversePrimary as per AUTOCOLOR_GUIDE.txt
    QString col = m_colors.value("$inversePrimary", m_colors.value("$primary", "#d1e1ff")).toString();
    return QColor(col);
}

QColor ThemeManager::backgroundColor() const {
    QString col = m_colors.value("$background", "#1a1c1e").toString();
    return QColor(col);
}

QColor ThemeManager::surfaceColor() const {
    QString col = m_colors.value("$surfaceContainer", "#1e1f22").toString();
    return QColor(col);
}

QColor ThemeManager::textColor() const {
    QString col = m_colors.value("$onSurface", "#e2e2e6").toString();
    return QColor(col);
}

QColor ThemeManager::onSurfaceVariant() const {
    QString col = m_colors.value("$onSurfaceVariant", "#c4c6cf").toString();
    return QColor(col);
}
