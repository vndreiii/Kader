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
    Q_PROPERTY(QString mimeFilter   READ mimeFilter   WRITE setMimeFilter   NOTIFY mimeFilterChanged)
    Q_PROPERTY(int contentWidth     READ contentWidth WRITE setContentWidth NOTIFY contentWidthChanged)

public:
    enum FilterMode { AllMode = 0, FavoritesMode = 1, TrashMode = 2, HiddenMode = 3 };
    Q_ENUM(FilterMode)

    enum Roles {
        IsHeaderRole    = Qt::UserRole + 1,
        MonthNameRole,
        ItemsRole,
        HeightMultRole
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
    Q_INVOKABLE void setFolderFilter(const QString &folder);

    QString searchFilter() const { return m_searchFilter; }
    Q_INVOKABLE void setSearchFilter(const QString &query);

    QString mimeFilter() const { return m_mimeFilter; }
    Q_INVOKABLE void setMimeFilter(const QString &prefix);

    int contentWidth() const { return m_contentWidth; }
    Q_INVOKABLE void setContentWidth(int px);

    Q_INVOKABLE void refresh(bool hideIgnored = true);
    Q_INVOKABLE QVariantList getFlatMediaList() const;

signals:
    void filterModeChanged();
    void numColumnsChanged();
    void folderFilterChanged();
    void searchFilterChanged();
    void mimeFilterChanged();
    void contentWidthChanged();

private:
    // Each row is either a month header or a strip of up to numColumns photos.
    struct Row {
        bool         isHeader = false;
        QString      monthName;
        QVariantList items;
        float        heightMult = 1.0f;
    };

    DatabaseManager *m_db;
    QList<Row>       m_rows;
    FilterMode       m_filterMode = AllMode;
    int              m_numColumns = 4;
    int              m_contentWidth = 1200;
    QString          m_folderFilter;
    QString          m_searchFilter;
    QString          m_mimeFilter;
};
