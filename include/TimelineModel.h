#pragma once

#include <QAbstractListModel>
#include <QVariantList>
#include "DatabaseManager.h"

class TimelineModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(FilterMode filterMode READ filterMode WRITE setFilterMode NOTIFY filterModeChanged)
    Q_PROPERTY(int numColumns READ numColumns WRITE setNumColumns NOTIFY numColumnsChanged)
    // 0 mosaic (justified rows), 1 grid (square cells), 2 list (one per row)
    Q_PROPERTY(int layoutMode READ layoutMode WRITE setLayoutMode NOTIFY layoutModeChanged)
    Q_PROPERTY(QString folderFilter READ folderFilter WRITE setFolderFilter NOTIFY folderFilterChanged)
    Q_PROPERTY(QString searchFilter READ searchFilter WRITE setSearchFilter NOTIFY searchFilterChanged)
    Q_PROPERTY(QString mimeFilter   READ mimeFilter   WRITE setMimeFilter   NOTIFY mimeFilterChanged)
    Q_PROPERTY(int contentWidth     READ contentWidth WRITE setContentWidth NOTIFY contentWidthChanged)
    Q_PROPERTY(bool aiFilterActive  READ aiFilterActive NOTIFY aiFilterActiveChanged)
    Q_PROPERTY(int sortRole  READ sortRole  WRITE setSortRole  NOTIFY sortRoleChanged)
    Q_PROPERTY(int sortOrder READ sortOrder WRITE setSortOrder NOTIFY sortOrderChanged)
    Q_PROPERTY(bool groupingEnabled READ groupingEnabled NOTIFY sortRoleChanged)
    // false until the first refresh() — views show a loading skeleton meanwhile
    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)


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

    bool aiFilterActive() const { return m_aiFilterActive; }
    Q_INVOKABLE void setAiFilter(const QVariantList &ids);
    Q_INVOKABLE void clearAiFilter();

    int  layoutMode() const { return m_layoutMode; }
    void setLayoutMode(int mode);
    int  sortRole()  const { return m_sortRole; }
    void setSortRole(int role);
    int  sortOrder() const { return m_sortOrder; }
    void setSortOrder(int order);
    bool groupingEnabled() const;

    Q_INVOKABLE void refresh(bool hideIgnored = true);
    bool loaded() const { return m_loaded; }
    Q_INVOKABLE QVariantList getFlatMediaList() const;
    Q_INVOKABLE QString monthAtRow(int row) const;
    Q_INVOKABLE void markAsViewed(int mediaId);
    Q_INVOKABLE QStringList getAvailableMimeTypes() const;
    Q_INVOKABLE QVariantList availableTypes() const;   // [{label, filter}]

    // Exact layout — the grid uses these instead of ListView's estimated
    // contentHeight, so large libraries scroll precisely (no bottom spring-back).
    Q_INVOKABLE void setLayoutMetrics(int rowSpacing, int headerHeight);
    Q_INVOKABLE int  totalContentHeight() const { return m_totalHeight; }
    Q_INVOKABLE int  rowY(int row) const;        // top Y of a row
    Q_INVOKABLE int  rowH(int row) const;        // pixel height of a row
    Q_INVOKABLE int  firstRowAtY(int y) const;   // row whose band contains Y
    Q_INVOKABLE QVariantMap rowData(int row) const;

signals:
    void loadedChanged();
    void layoutChanged();
    void filterModeChanged();
    void numColumnsChanged();
    void layoutModeChanged();
    void folderFilterChanged();
    void searchFilterChanged();
    void mimeFilterChanged();
    void contentWidthChanged();
    void aiFilterActiveChanged();
    void sortRoleChanged();
    void sortOrderChanged();

private:
    bool m_loaded = false;
    // Each row is either a month header or a strip of up to numColumns photos.
    struct Row {
        bool         isHeader = false;
        QString      monthName;
        QVariantList items;
        float        heightMult = 1.0f;
    };

    void rebuildLayout();

    // Pack m_media into rows for the current width/column count. Split out of
    // refresh() so geometry-only changes (window resize, mosaic density) can
    // re-pack without re-running the library-wide SELECT and its filter passes.
    void repack();

    DatabaseManager *m_db;
    QVariantList     m_media;            // queried + filtered items, input to repack()
    QList<Row>       m_rows;
    QList<int>       m_rowY;             // cumulative top Y per row
    int              m_totalHeight = 0;
    int              m_rowSpacing  = 6;
    int              m_headerHeight = 56;
    FilterMode       m_filterMode = AllMode;
    int              m_numColumns = 4;
    int              m_contentWidth = 1200;
    QString          m_folderFilter;
    QString          m_searchFilter;
    QString          m_mimeFilter;
    QList<int>       m_aiFilterIds;
    bool             m_aiFilterActive = false;
    int              m_layoutMode = 0;
    int              m_sortRole  = 0; // DatabaseManager::ByCreated
    int              m_sortOrder = 0; // DatabaseManager::Descending
};
