#pragma once

#include <QObject>
#include <QColor>
#include <QVariantMap>
#include <QFileSystemWatcher>

class ThemeManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QColor primaryColor READ primaryColor NOTIFY themeChanged)
    Q_PROPERTY(QColor backgroundColor READ backgroundColor NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceColor READ surfaceColor NOTIFY themeChanged)
    Q_PROPERTY(QColor textColor READ textColor NOTIFY themeChanged)
    Q_PROPERTY(QColor onSurfaceVariant READ onSurfaceVariant NOTIFY themeChanged)

public:
    explicit ThemeManager(QObject *parent = nullptr);

    QColor primaryColor() const;
    QColor backgroundColor() const;
    QColor surfaceColor() const;
    QColor textColor() const;
    QColor onSurfaceVariant() const;

    Q_INVOKABLE void refreshTheme();

signals:
    void themeChanged();

private:
    void parseScss();
    QString getScssPath() const;

    QVariantMap m_colors;
    QFileSystemWatcher *m_watcher;
};
