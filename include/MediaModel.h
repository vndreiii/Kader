#pragma once

#include <QAbstractListModel>
#include <QVariantList>
#include <QStringList>

class DatabaseManager;
class ThumbnailGenerator;

class MediaModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum MediaRoles {
        IdRole = Qt::UserRole + 1,
        PathRole,
        ThumbRole,
        DateRole,
        MimeRole,
        WidthRole,
        HeightRole,
        SectionRole
    };

    explicit MediaModel(DatabaseManager *db, ThumbnailGenerator *thumb, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void refresh();

private:
    DatabaseManager *m_db;
    ThumbnailGenerator *m_thumb;
    QVariantList m_data;
};
