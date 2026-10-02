#pragma once

#include <QAbstractListModel>
#include <QAbstractAnimation>
#include <QColor>
#include <QElapsedTimer>
#include <QHash>
#include <QPointF>
#include <QTimer>
#include <QQuickItem>
#include <QVariantList>
#include <QVector>
#include <memory>

#include "kader_core.h"

class GlobeItem;

// Fixed pool of label slots: a label keeps its slot while it stays on screen,
// so QML delegates are never created or destroyed while the globe moves.
class GlobeLabelModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles { TextRole = Qt::UserRole + 1, XRole, YRole, OpacityRole, ClassRole, AnchorRole, CapitalRole };
    static constexpr int kSlots = 320;

    explicit GlobeLabelModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void apply(const KgLabel *labels, uint32_t count, const KgWorld *world);
    void clear();

private:
    struct Slot {
        quint32 id = 0;
        bool used = false;
        QString text;
        float x = 0, y = 0, opacity = 0;
        quint8 cls = 0, anchor = 0, capital = 0;
    };
    QVector<Slot> m_slots;
    QHash<quint32, int> m_slotOf;
};

// One row per pin cluster; rows are reset only when clustering changes.
class GlobePinModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles { XRole = Qt::UserRole + 1, YRole, DepthRole, OpacityRole, ShownRole,
                 CountRole, MembersRole, LeadRole, ThumbRole, ClusterRole };

    explicit GlobePinModel(GlobeItem *globe);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void apply(KgGlobe *g, const KgPin *pins, uint32_t count, uint32_t epoch);
    void invalidate() { m_epoch = UINT32_MAX; }

private:
    struct Row {
        float x = 0, y = 0, depth = 0, opacity = 0;
        bool shown = false;
        quint32 count = 0, members = 0, lead = 0;
    };
    GlobeItem *m_globe;
    QVector<Row> m_rows;
    quint32 m_epoch = UINT32_MAX;
};

// Interactive vector globe: dotted land that refines with zoom, coastlines,
// country/state borders, decluttered place labels and clustered photo pins.
// Geometry comes from the Rust geo engine (rust/kader-core); this item owns
// input, animation pacing and the scene-graph nodes.
class GlobeItem : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(QVariantList locations READ locations WRITE setLocations NOTIFY locationsChanged)
    Q_PROPERTY(QColor oceanColor MEMBER m_oceanColor NOTIFY styleChanged)
    Q_PROPERTY(QColor oceanEdgeColor MEMBER m_oceanEdgeColor NOTIFY styleChanged)
    Q_PROPERTY(QColor glowColor MEMBER m_glowColor NOTIFY styleChanged)
    Q_PROPERTY(QColor landColor MEMBER m_landColor NOTIFY styleChanged)
    Q_PROPERTY(QColor coastColor MEMBER m_coastColor NOTIFY styleChanged)
    Q_PROPERTY(QColor borderColor MEMBER m_borderColor NOTIFY styleChanged)
    Q_PROPERTY(QColor stateColor MEMBER m_stateColor NOTIFY styleChanged)
    Q_PROPERTY(QColor cityColor MEMBER m_cityColor NOTIFY styleChanged)
    Q_PROPERTY(QColor cityHaloColor MEMBER m_cityHaloColor NOTIFY styleChanged)
    Q_PROPERTY(QColor casingColor MEMBER m_casingColor NOTIFY styleChanged)
    Q_PROPERTY(qreal dotSpacing MEMBER m_dotSpacing NOTIFY styleChanged)
    Q_PROPERTY(qreal labelDensity MEMBER m_labelDensity NOTIFY styleChanged)
    Q_PROPERTY(QSizeF pinSize MEMBER m_pinSize NOTIFY styleChanged)
    Q_PROPERTY(bool autoRotate READ autoRotate WRITE setAutoRotate NOTIFY autoRotateChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(QAbstractListModel *labels READ labels CONSTANT)
    Q_PROPERTY(QAbstractListModel *pins READ pins CONSTANT)
    Q_PROPERTY(qreal zoomLevel READ zoomLevel NOTIFY cameraChanged)
    Q_PROPERTY(qreal centerLat READ centerLat NOTIFY cameraChanged)
    Q_PROPERTY(qreal centerLon READ centerLon NOTIFY cameraChanged)
    Q_PROPERTY(qreal globeRadius READ globeRadius NOTIFY cameraChanged)
    Q_PROPERTY(int hoveredCluster READ hoveredCluster NOTIFY hoveredClusterChanged)

public:
    explicit GlobeItem(QQuickItem *parent = nullptr);
    ~GlobeItem() override;

    QVariantList locations() const { return m_locations; }
    void setLocations(const QVariantList &locations);
    bool autoRotate() const { return m_autoRotate; }
    void setAutoRotate(bool on);
    bool ready() const { return m_world != nullptr; }
    QAbstractListModel *labels() { return &m_labelModel; }
    QAbstractListModel *pins() { return &m_pinModel; }
    qreal zoomLevel() const { return m_cam.zoom; }
    qreal centerLat() const { return m_cam.lat; }
    qreal centerLon() const { return m_cam.lon; }
    qreal globeRadius() const { return m_cam.radius; }
    int hoveredCluster() const { return m_hovered; }

    // Fly to a place. `km` is the width of the region to frame (0 keeps zoom).
    Q_INVOKABLE void flyTo(double lat, double lon, double km = 0);
    Q_INVOKABLE void zoomIn();
    Q_INVOKABLE void zoomOut();
    Q_INVOKABLE void zoomBy(double factor, double x, double y);
    Q_INVOKABLE void resetView();
    // {x, y, visible} of a lat/lon in item coordinates.
    Q_INVOKABLE QVariantMap project(double lat, double lon);
    // Locations (entries of `locations`) grouped in a cluster.
    Q_INVOKABLE QVariantList clusterMembers(int cluster);
    // {lat, lon, count, lead} of a cluster.
    Q_INVOKABLE QVariantMap clusterInfo(int cluster);
    // Zoom into a cluster until it splits (or to street level).
    Q_INVOKABLE void expandCluster(int cluster);
    // Offline "City, Country" of the nearest town (empty until `ready`).
    Q_INVOKABLE QString placeName(double lat, double lon, double maxKm = 40) const;
    // {name, km} of the nearest town within maxKm ({} when none / not ready).
    Q_INVOKABLE QVariantMap placeInfo(double lat, double lon, double maxKm = 250) const;

    KgGlobe *engine() const { return m_globe; }
    QVariant locationAt(int index) const { return m_locations.value(index); }

signals:
    void locationsChanged();
    void styleChanged();
    void autoRotateChanged();
    void readyChanged();
    void cameraChanged();
    void hoveredClusterChanged();
    void frameUpdated();
    void pinClicked(int cluster);
    void globeClicked(double lat, double lon);
    void interactionStarted();

protected:
    QSGNode *updatePaintNode(QSGNode *old, UpdatePaintNodeData *) override;
    void updatePolish() override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void itemChange(ItemChange change, const ItemChangeData &value) override;
    void mousePressEvent(QMouseEvent *e) override;
    void mouseMoveEvent(QMouseEvent *e) override;
    void mouseReleaseEvent(QMouseEvent *e) override;
    void mouseDoubleClickEvent(QMouseEvent *e) override;
    void hoverMoveEvent(QHoverEvent *e) override;
    void hoverLeaveEvent(QHoverEvent *e) override;
    void wheelEvent(QWheelEvent *e) override;
    void keyPressEvent(QKeyEvent *e) override;
    void touchEvent(QTouchEvent *e) override;

private:
    friend class GlobeTicker;
    void onTick();
    void requestFrame();
    void ensureTicking();
    void pushStyle();
    void pushViewport();
    void loadWorld();
    void setHovered(int cluster);

    KgGlobe *m_globe = nullptr;
    const KgWorld *m_world = nullptr;
    std::unique_ptr<QAbstractAnimation> m_ticker;
    QElapsedTimer m_clock;
    QTimer m_idleWake;
    double m_pendingDt = 0;
    bool m_animating = false;
    bool m_fading = false;

    KgFrame m_frame{};
    bool m_geometryDirty = true;
    KgCamera m_cam{};

    GlobeLabelModel m_labelModel;
    GlobePinModel m_pinModel;
    QVariantList m_locations;

    // input
    QPointF m_pressPos, m_lastPos;
    bool m_pressed = false, m_dragging = false;
    struct Sample { QPointF pos; qint64 t; };
    QVector<Sample> m_samples;
    QElapsedTimer m_inputClock;
    int m_hovered = -1;
    double m_pinchScale = 1.0;

    // style
    QColor m_oceanColor{0x0b, 0x10, 0x1c};
    QColor m_oceanEdgeColor{0x05, 0x07, 0x0d};
    QColor m_glowColor{0x6f, 0x9b, 0xff, 140};
    QColor m_landColor{0xe8, 0xec, 0xf6, 235};
    QColor m_coastColor{0x8f, 0xb0, 0xff, 200};
    QColor m_borderColor{0xff, 0xff, 0xff, 215};
    QColor m_stateColor{0xff, 0xff, 0xff, 105};
    QColor m_cityColor{0xff, 0xff, 0xff};
    QColor m_cityHaloColor{0x0a, 0x0c, 0x14, 200};
    QColor m_casingColor{0x06, 0x08, 0x0e, 200};
    qreal m_dotSpacing = 7.0;
    qreal m_labelDensity = 0.0;
    QSizeF m_pinSize{64, 44};
    bool m_autoRotate = true;
};
