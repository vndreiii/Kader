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
        SectionRole,
        SelectedRole
    };

    explicit MediaModel(DatabaseManager *db, ThumbnailGenerator *thumb, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    bool setData(const QModelIndex &index, const QVariant &value, int role = Qt::EditRole) override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void refresh(bool hideIgnored = true);
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE QStringList getSelectedPaths() const;

private:
    DatabaseManager *m_db;
    ThumbnailGenerator *m_thumb;
    QVariantList m_data;
};
