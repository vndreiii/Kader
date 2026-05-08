#pragma once

#include <QAbstractListModel>
#include <QVariantList>

class DatabaseManager;

struct MonthGroup {
    QString name;
    QVariantList items;
};

class TimelineModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(FilterMode filterMode READ filterMode WRITE setFilterMode NOTIFY filterModeChanged)

public:
    enum FilterMode {
        AllMode,
        FavoritesMode,
        TrashMode
    };
    Q_ENUM(FilterMode)

    enum TimelineRoles {
        NameRole = Qt::UserRole + 1,
        ItemsRole
    };

    explicit TimelineModel(DatabaseManager *db, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    FilterMode filterMode() const { return m_filterMode; }
    void setFilterMode(FilterMode mode);

    Q_INVOKABLE void refresh(bool hideIgnored = true);

signals:
    void filterModeChanged();

private:
    DatabaseManager *m_db;
    QList<MonthGroup> m_groups;
    FilterMode m_filterMode = AllMode;
};
