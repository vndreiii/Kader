#pragma once

#include <QAbstractListModel>
#include <QVariantList>

class DatabaseManager;
class ThumbnailGenerator;

class AlbumModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum AlbumRoles {
        NameRole = Qt::UserRole + 1,
        PathRole,
        CountRole,
        SizeRole,
        CoverRole
    };

    explicit AlbumModel(DatabaseManager *db, ThumbnailGenerator *thumb, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void refresh(bool hideIgnored = true);

    QString searchFilter() const { return m_searchFilter; }
    Q_INVOKABLE void setSearchFilter(const QString &query);

signals:
    void searchFilterChanged();

private:
    DatabaseManager *m_db;
    ThumbnailGenerator *m_thumb;
    QVariantList m_data;
    QString m_searchFilter;
};
