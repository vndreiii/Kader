#pragma once

#include <QAbstractListModel>
#include <QVariantList>

class DatabaseManager;

class TimelineModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(FilterMode filterMode READ filterMode WRITE setFilterMode NOTIFY filterModeChanged)
    Q_PROPERTY(int numColumns READ numColumns WRITE setNumColumns NOTIFY numColumnsChanged)
    Q_PROPERTY(QString folderFilter READ folderFilter WRITE setFolderFilter NOTIFY folderFilterChanged)
    Q_PROPERTY(QString searchFilter READ searchFilter WRITE setSearchFilter NOTIFY searchFilterChanged)

public:
    enum FilterMode { AllMode = 0, FavoritesMode = 1, TrashMode = 2 };
    Q_ENUM(FilterMode)

    enum Roles {
        IsHeaderRole  = Qt::UserRole + 1,
        MonthNameRole,
        ItemsRole
    };

    explicit TimelineModel(DatabaseManager *db, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    FilterMode filterMode() const { return m_filterMode; }
    void setFilterMode(FilterMode mode);

    int numColumns() const { return m_numColumns; }
    void setNumColumns(int n);

    QString folderFilter() const { return m_folderFilter; }
    void setFolderFilter(const QString &folder);

    QString searchFilter() const { return m_searchFilter; }
    void setSearchFilter(const QString &query);

    Q_INVOKABLE void refresh(bool hideIgnored = true);
    Q_INVOKABLE QVariantList getFlatMediaList() const;

signals:
    void filterModeChanged();
    void numColumnsChanged();
    void folderFilterChanged();
    void searchFilterChanged();

private:
    // Each row is either a month header or a strip of up to numColumns photos.
    struct Row {
        bool       isHeader = false;
        QString    monthName;
        QVariantList items;
    };

    DatabaseManager *m_db;
    QList<Row>       m_rows;
    FilterMode       m_filterMode = AllMode;
    int              m_numColumns = 4;
    QString          m_folderFilter;
    QString          m_searchFilter;
};
