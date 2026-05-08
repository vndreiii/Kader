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
public:
    enum TimelineRoles {
        NameRole = Qt::UserRole + 1,
        ItemsRole
    };

    explicit TimelineModel(DatabaseManager *db, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void refresh(bool hideIgnored = true);

private:
    DatabaseManager *m_db;
    QList<MonthGroup> m_groups;
};
