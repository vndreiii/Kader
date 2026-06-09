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
        CoverRole,
        PinnedRole,
        DescriptionRole,
        CoverPathRole
    };

    explicit AlbumModel(DatabaseManager *db, ThumbnailGenerator *thumb, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void refresh(bool hideIgnored = true);

    QString searchFilter() const { return m_searchFilter; }
    Q_INVOKABLE void setSearchFilter(const QString &query);
    Q_PROPERTY(QString searchFilter READ searchFilter WRITE setSearchFilter NOTIFY searchFilterChanged)

    // Sorting (in-memory; albums are few). Pinned albums always stay first.
    enum AlbumSortRole { ByName = 0, ByCount = 1, BySize = 2 };
    Q_ENUM(AlbumSortRole)

    int sortRole()  const { return m_sortRole; }
    int sortOrder() const { return m_sortOrder; }
    Q_INVOKABLE void setSortRole(int role);
    Q_INVOKABLE void setSortOrder(int order);
    Q_PROPERTY(int sortRole  READ sortRole  WRITE setSortRole  NOTIFY sortRoleChanged)
    Q_PROPERTY(int sortOrder READ sortOrder WRITE setSortOrder NOTIFY sortOrderChanged)

signals:
    void searchFilterChanged();
    void sortRoleChanged();
    void sortOrderChanged();

private:
    void applySort();

    DatabaseManager *m_db;
    ThumbnailGenerator *m_thumb;
    QVariantList m_data;
    QString m_searchFilter;
    int m_sortRole  = 0;   // ByName
    int m_sortOrder = 1;   // 1 = ascending (A→Z), 0 = descending
};
