#include "GlobeItem.h"

#include <QFile>
#include <QFutureWatcher>
#include <QQuickWindow>
#include <QSGGeometryNode>
#include <QSGMaterial>
#include <QSGMaterialShader>
#include <QtConcurrent>
#include <QtMath>
#include <cstring>
#include <mutex>

// ── shared world dataset ─────────────────────────────────────────────────────
// Immutable once decoded, so every globe instance (and thread) shares one copy.
namespace {

struct WorldHolder {
    std::once_flag once;
    QFuture<KgWorld *> future;
    KgWorld *world = nullptr;
    ~WorldHolder() { kg_world_free(world); }
};

WorldHolder &worldHolder() {
    static WorldHolder h;
    return h;
}

QFuture<KgWorld *> worldFuture() {
    WorldHolder &h = worldHolder();
    std::call_once(h.once, [&h] {
        h.future = QtConcurrent::run([]() -> KgWorld * {
            QFile f(QStringLiteral(":/Kader/assets/geo/world.kgeo"));
            if (!f.open(QIODevice::ReadOnly)) {
                qWarning("GlobeItem: world dataset missing from resources");
                return nullptr;
            }
            const QByteArray data = f.readAll();
            KgWorld *w = kg_world_new(reinterpret_cast<const uint8_t *>(data.constData()),
                                      size_t(data.size()));
            if (!w)
                qWarning("GlobeItem: world dataset failed to decode");
            return w;
        });
    });
    return h.future;
}

inline void rgba(const QColor &c, uint8_t out[4]) {
    out[0] = uint8_t(c.red());
    out[1] = uint8_t(c.green());
    out[2] = uint8_t(c.blue());
    out[3] = uint8_t(c.alpha());
}

// ── scene graph: antialiased shape batch ─────────────────────────────────────

const QSGGeometry::AttributeSet &shapeAttributes() {
    static const QSGGeometry::Attribute attrs[] = {
        QSGGeometry::Attribute::createWithAttributeType(0, 2, QSGGeometry::FloatType, QSGGeometry::PositionAttribute),
        QSGGeometry::Attribute::createWithAttributeType(1, 2, QSGGeometry::FloatType, QSGGeometry::TexCoordAttribute),
        QSGGeometry::Attribute::createWithAttributeType(2, 1, QSGGeometry::FloatType, QSGGeometry::TexCoord1Attribute),
        QSGGeometry::Attribute::createWithAttributeType(3, 4, QSGGeometry::UnsignedByteType, QSGGeometry::ColorAttribute),
    };
    static const QSGGeometry::AttributeSet set = {4, sizeof(KgVertex), attrs};
    static_assert(sizeof(KgVertex) == 24, "KgVertex layout");
    return set;
}

class ShapeShader : public QSGMaterialShader {
public:
    ShapeShader() {
        setShaderFileName(VertexStage, QStringLiteral(":/shaders/globe_shape.vert.qsb"));
        setShaderFileName(FragmentStage, QStringLiteral(":/shaders/globe_shape.frag.qsb"));
    }
    bool updateUniformData(RenderState &state, QSGMaterial *, QSGMaterial *) override {
        QByteArray *buf = state.uniformData();
        bool changed = false;
        if (state.isMatrixDirty()) {
            const QMatrix4x4 m = state.combinedMatrix();
            std::memcpy(buf->data(), m.constData(), 64);
            changed = true;
        }
        if (state.isOpacityDirty()) {
            const float o = state.opacity();
            std::memcpy(buf->data() + 64, &o, 4);
            changed = true;
        }
        return changed;
    }
};

class ShapeMaterial : public QSGMaterial {
public:
    ShapeMaterial() { setFlag(Blending); }
    QSGMaterialType *type() const override {
        static QSGMaterialType t;
        return &t;
    }
    QSGMaterialShader *createShader(QSGRendererInterface::RenderMode) const override { return new ShapeShader; }
    int compare(const QSGMaterial *) const override { return 0; }
};

// ── scene graph: ocean sphere + atmosphere ───────────────────────────────────

struct SphereUniforms {
    float center[2];
    float radius;
    float dpr;
    float ocean[4];
    float edge[4];
    float glow[4];
    float glowWidth;
};

class SphereMaterial : public QSGMaterial {
public:
    SphereMaterial() { setFlag(Blending); }
    QSGMaterialType *type() const override {
        static QSGMaterialType t;
        return &t;
    }
    QSGMaterialShader *createShader(QSGRendererInterface::RenderMode) const override;
    int compare(const QSGMaterial *other) const override {
        return std::memcmp(&u, &static_cast<const SphereMaterial *>(other)->u, sizeof(u));
    }
    SphereUniforms u{};
};

class SphereShader : public QSGMaterialShader {
public:
    SphereShader() {
        setShaderFileName(VertexStage, QStringLiteral(":/shaders/globe_sphere.vert.qsb"));
        setShaderFileName(FragmentStage, QStringLiteral(":/shaders/globe_sphere.frag.qsb"));
    }
    bool updateUniformData(RenderState &state, QSGMaterial *mat, QSGMaterial *) override {
        // std140: mat4 @0, float opacity @64, vec2 center @72, float radius @80,
        // float dpr @84, vec4 ocean @96, vec4 edge @112, vec4 glow @128,
        // float glowWidth @144.
        QByteArray *buf = state.uniformData();
        char *d = buf->data();
        if (state.isMatrixDirty())
            std::memcpy(d, state.combinedMatrix().constData(), 64);
        if (state.isOpacityDirty()) {
            const float o = state.opacity();
            std::memcpy(d + 64, &o, 4);
        }
        const SphereUniforms &u = static_cast<SphereMaterial *>(mat)->u;
        std::memcpy(d + 72, u.center, 8);
        std::memcpy(d + 80, &u.radius, 4);
        std::memcpy(d + 84, &u.dpr, 4);
        std::memcpy(d + 96, u.ocean, 16);
        std::memcpy(d + 112, u.edge, 16);
        std::memcpy(d + 128, u.glow, 16);
        std::memcpy(d + 144, &u.glowWidth, 4);
        return true;
    }
};

QSGMaterialShader *SphereMaterial::createShader(QSGRendererInterface::RenderMode) const {
    return new SphereShader;
}

void colorToVec4(const QColor &c, float out[4]) {
    out[0] = float(c.redF());
    out[1] = float(c.greenF());
    out[2] = float(c.blueF());
    out[3] = float(c.alphaF());
}

class GlobeRootNode : public QSGNode {
public:
    GlobeRootNode() {
        sphere.setGeometry(new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), 4));
        sphere.geometry()->setDrawingMode(QSGGeometry::DrawTriangleStrip);
        sphere.setMaterial(new SphereMaterial);
        sphere.setFlags(QSGNode::OwnsGeometry | QSGNode::OwnsMaterial);
        appendChildNode(&sphere);

        auto *g = new QSGGeometry(shapeAttributes(), 0, 0, QSGGeometry::UnsignedIntType);
        g->setDrawingMode(QSGGeometry::DrawTriangles);
        g->setVertexDataPattern(QSGGeometry::StreamPattern);
        g->setIndexDataPattern(QSGGeometry::StreamPattern);
        shapes.setGeometry(g);
        shapes.setMaterial(new ShapeMaterial);
        shapes.setFlags(QSGNode::OwnsGeometry | QSGNode::OwnsMaterial);
        appendChildNode(&shapes);
    }
    ~GlobeRootNode() override {
        removeChildNode(&sphere);
        removeChildNode(&shapes);
    }
    QSGGeometryNode sphere;
    QSGGeometryNode shapes;
};

} // namespace

// Drives the globe from Qt Quick's animation driver: vsync-paced on the
// threaded render loop, and paused whenever nothing moves.
class GlobeTicker : public QAbstractAnimation {
public:
    explicit GlobeTicker(GlobeItem *item) : m_item(item) {}
    int duration() const override { return -1; }

protected:
    void updateCurrentTime(int) override { m_item->onTick(); }

private:
    GlobeItem *m_item;
};

// ── GlobeLabelModel ──────────────────────────────────────────────────────────

GlobeLabelModel::GlobeLabelModel(QObject *parent) : QAbstractListModel(parent), m_slots(kSlots) {}

int GlobeLabelModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : kSlots;
}

QVariant GlobeLabelModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_slots.size())
        return {};
    const Slot &s = m_slots[index.row()];
    switch (role) {
    case TextRole: return s.text;
    case XRole: return s.x;
    case YRole: return s.y;
    case OpacityRole: return s.used ? s.opacity : 0.0f;
    case ClassRole: return int(s.cls);
    case AnchorRole: return int(s.anchor);
    case CapitalRole: return bool(s.capital);
    }
    return {};
}

QHash<int, QByteArray> GlobeLabelModel::roleNames() const {
    return {{TextRole, "ltext"}, {XRole, "lx"}, {YRole, "ly"}, {OpacityRole, "lopacity"},
            {ClassRole, "lclass"}, {AnchorRole, "lanchor"}, {CapitalRole, "lcapital"}};
}

void GlobeLabelModel::clear() {
    for (Slot &s : m_slots)
        s.used = false;
    m_slotOf.clear();
    emit dataChanged(index(0), index(kSlots - 1), {OpacityRole});
}

void GlobeLabelModel::apply(const KgLabel *labels, uint32_t count, const KgWorld *world) {
    // Release slots whose label left the screen.
    QSet<quint32> present;
    present.reserve(int(count));
    for (uint32_t i = 0; i < count; ++i)
        present.insert(labels[i].id);
    int lo = kSlots, hi = -1;
    bool textChanged = false;
    for (auto it = m_slotOf.begin(); it != m_slotOf.end();) {
        if (!present.contains(it.key())) {
            Slot &s = m_slots[it.value()];
            s.used = false;
            lo = std::min(lo, it.value());
            hi = std::max(hi, it.value());
            it = m_slotOf.erase(it);
        } else {
            ++it;
        }
    }
    int free = 0;
    for (uint32_t i = 0; i < count; ++i) {
        const KgLabel &l = labels[i];
        int slot = m_slotOf.value(l.id, -1);
        if (slot < 0) {
            while (free < kSlots && m_slots[free].used)
                ++free;
            if (free >= kSlots)
                continue; // pool exhausted; the engine caps labels well below this
            slot = free;
            m_slotOf.insert(l.id, slot);
            Slot &s = m_slots[slot];
            s.used = true;
            s.id = l.id;
            size_t len = 0;
            const uint8_t *name = kg_world_label_name(world, l.id, &len);
            s.text = QString::fromUtf8(reinterpret_cast<const char *>(name), qsizetype(len));
            s.cls = l.cls;
            s.capital = l.capital;
            textChanged = true;
        }
        Slot &s = m_slots[slot];
        s.x = l.x;
        s.y = l.y;
        s.opacity = l.alpha;
        s.anchor = l.anchor;
        lo = std::min(lo, slot);
        hi = std::max(hi, slot);
    }
    if (hi < lo)
        return;
    if (textChanged)
        emit dataChanged(index(lo), index(hi));
    else
        emit dataChanged(index(lo), index(hi), {XRole, YRole, OpacityRole, AnchorRole});
}

// ── GlobePinModel ────────────────────────────────────────────────────────────

GlobePinModel::GlobePinModel(GlobeItem *globe) : QAbstractListModel(globe), m_globe(globe) {}

int GlobePinModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant GlobePinModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};
    const Row &r = m_rows[index.row()];
    switch (role) {
    case XRole: return r.x;
    case YRole: return r.y;
    case DepthRole: return r.depth;
    case OpacityRole: return r.shown ? r.opacity : 0.0f;
    case ShownRole: return r.shown;
    case CountRole: return int(r.count);
    case MembersRole: return int(r.members);
    case LeadRole: return int(r.lead);
    case ClusterRole: return index.row();
    case ThumbRole: return m_globe->locationAt(int(r.lead)).toMap().value(QStringLiteral("thumb"));
    }
    return {};
}

QHash<int, QByteArray> GlobePinModel::roleNames() const {
    return {{XRole, "px"}, {YRole, "py"}, {DepthRole, "depth"}, {OpacityRole, "popacity"},
            {ShownRole, "shown"}, {CountRole, "count"}, {MembersRole, "members"},
            {LeadRole, "lead"}, {ThumbRole, "thumb"}, {ClusterRole, "cluster"}};
}

void GlobePinModel::apply(KgGlobe *g, const KgPin *pins, uint32_t count, uint32_t epoch) {
    if (epoch != m_epoch) {
        beginResetModel();
        m_epoch = epoch;
        const uint32_t n = kg_globe_cluster_count(g);
        m_rows.assign(int(n), Row{});
        for (uint32_t i = 0; i < n; ++i) {
            uint32_t weight = 0, lead = 0;
            kg_globe_cluster_info(g, i, nullptr, nullptr, &weight, &lead);
            size_t members = 0;
            kg_globe_pin_members(g, i, &members);
            m_rows[int(i)].count = weight;
            m_rows[int(i)].lead = lead;
            m_rows[int(i)].members = quint32(members);
        }
        endResetModel();
    }
    for (Row &r : m_rows)
        r.shown = false;
    for (uint32_t i = 0; i < count; ++i) {
        const KgPin &p = pins[i];
        if (p.cluster >= uint32_t(m_rows.size()))
            continue;
        Row &r = m_rows[int(p.cluster)];
        r.x = p.x;
        r.y = p.y;
        r.depth = p.depth;
        r.opacity = p.alpha;
        r.shown = true;
    }
    if (!m_rows.isEmpty())
        emit dataChanged(index(0), index(int(m_rows.size()) - 1),
                         {XRole, YRole, DepthRole, OpacityRole, ShownRole});
}

// ── GlobeItem ────────────────────────────────────────────────────────────────

GlobeItem::GlobeItem(QQuickItem *parent)
    : QQuickItem(parent), m_globe(kg_globe_new()), m_ticker(new GlobeTicker(this)), m_pinModel(this) {
    setFlag(ItemHasContents);
    setFlag(ItemIsFocusScope);
    setAcceptedMouseButtons(Qt::LeftButton | Qt::MiddleButton);
    setAcceptHoverEvents(true);
    setAcceptTouchEvents(true);
    setActiveFocusOnTab(true);
    m_inputClock.start();
    m_clock.start();
    m_idleWake.setSingleShot(true);
    m_idleWake.setInterval(2600);
    connect(&m_idleWake, &QTimer::timeout, this, [this] { ensureTicking(); });

    connect(this, &GlobeItem::styleChanged, this, [this] { pushStyle(); requestFrame(); });
    pushStyle();
    loadWorld();
}

GlobeItem::~GlobeItem() {
    m_ticker->stop();
    kg_globe_free(m_globe);
}

void GlobeItem::loadWorld() {
    QFuture<KgWorld *> f = worldFuture();
    auto adopt = [this](KgWorld *w) {
        m_world = w;
        emit readyChanged();
        requestFrame();
        ensureTicking();
    };
    if (f.isFinished()) {
        adopt(f.result());
        return;
    }
    auto *watcher = new QFutureWatcher<KgWorld *>(this);
    connect(watcher, &QFutureWatcher<KgWorld *>::finished, this, [watcher, adopt] {
        adopt(watcher->result());
        watcher->deleteLater();
    });
    watcher->setFuture(f);
}

void GlobeItem::pushStyle() {
    KgStyle s{};
    rgba(m_landColor, s.land);
    rgba(m_coastColor, s.coast);
    rgba(m_borderColor, s.border);
    rgba(m_stateColor, s.state);
    rgba(m_cityColor, s.city);
    rgba(m_cityHaloColor, s.city_halo);
    rgba(m_casingColor, s.casing);
    s.dot_spacing = float(m_dotSpacing);
    s.dot_size = 0.30f;
    s.coast_width = 0.9f;
    s.border_width = 1.15f;
    s.state_width = 0.75f;
    s.label_density = float(m_labelDensity);
    s.pin_width = float(m_pinSize.width());
    s.pin_height = float(m_pinSize.height());
    s.pin_merge = float(std::max(m_pinSize.width(), m_pinSize.height()) * 1.05);
    kg_globe_set_style(m_globe, &s);
}

void GlobeItem::pushViewport() {
    const qreal dpr = window() ? window()->effectiveDevicePixelRatio() : 1.0;
    kg_globe_set_viewport(m_globe, width(), height(), dpr);
}

void GlobeItem::setLocations(const QVariantList &locations) {
    m_locations = locations;
    QVector<KgPinIn> pins;
    pins.reserve(locations.size());
    for (const QVariant &v : locations) {
        const QVariantMap m = v.toMap();
        KgPinIn p{};
        p.lat = m.value(QStringLiteral("lat")).toDouble();
        p.lon = m.value(QStringLiteral("lon")).toDouble();
        p.weight = quint32(std::max(1, m.value(QStringLiteral("count"), 1).toInt()));
        pins.push_back(p);
    }
    kg_globe_set_pins(m_globe, pins.constData(), size_t(pins.size()));
    m_pinModel.invalidate();
    emit locationsChanged();
    requestFrame();
}

void GlobeItem::setAutoRotate(bool on) {
    if (on == m_autoRotate)
        return;
    m_autoRotate = on;
    kg_globe_set_auto_rotate(m_globe, on);
    emit autoRotateChanged();
    ensureTicking();
}

void GlobeItem::requestFrame() {
    m_geometryDirty = true;
    polish();
    ensureTicking();
}

void GlobeItem::ensureTicking() {
    if (!isVisible() || !window() || !m_world) {
        m_ticker->stop();
        return;
    }
    m_idleWake.stop();
    if (m_ticker->state() != QAbstractAnimation::Running)
        m_ticker->start(); // m_clock keeps running: the engine measures idle time across pauses
}

void GlobeItem::onTick() {
    const double dt = m_clock.restart() / 1000.0;
    m_animating = kg_globe_tick(m_globe, dt);
    m_pendingDt += dt;
    if (m_animating || m_fading || m_geometryDirty) {
        m_geometryDirty = true;
        polish();
    } else {
        m_ticker->stop(); // idle: no CPU or GPU work until the next input
        if (m_autoRotate)
            m_idleWake.start(); // resume to start the idle spin
    }
}

void GlobeItem::updatePolish() {
    if (!m_world || width() < 2 || height() < 2)
        return;
    pushViewport();
    m_fading = kg_globe_build(m_globe, m_world, m_pendingDt, &m_frame);
    m_pendingDt = 0;
    m_labelModel.apply(m_frame.labels, m_frame.label_count, m_world);
    m_pinModel.apply(m_globe, m_frame.pins, m_frame.pin_count, m_frame.pin_epoch);

    KgCamera cam{};
    kg_globe_camera(m_globe, &cam);
    const bool camMoved = cam.lat != m_cam.lat || cam.lon != m_cam.lon || cam.radius != m_cam.radius;
    m_cam = cam;
    if (camMoved)
        emit cameraChanged();
    emit frameUpdated();
    update();
    if (m_fading)
        ensureTicking();
}

QSGNode *GlobeItem::updatePaintNode(QSGNode *old, UpdatePaintNodeData *) {
    auto *root = static_cast<GlobeRootNode *>(old);
    if (!root)
        root = new GlobeRootNode;
    if (!m_geometryDirty)
        return root;
    m_geometryDirty = false;

    const float w = float(width()), h = float(height());
    // sphere: a quad over the item, shaded per pixel
    QSGGeometry *sg = root->sphere.geometry();
    QSGGeometry::Point2D *sp = sg->vertexDataAsPoint2D();
    sp[0].set(0, 0);
    sp[1].set(w, 0);
    sp[2].set(0, h);
    sp[3].set(w, h);
    root->sphere.markDirty(QSGNode::DirtyGeometry);

    auto *sm = static_cast<SphereMaterial *>(root->sphere.material());
    SphereUniforms u{};
    u.center[0] = w * 0.5f;
    u.center[1] = h * 0.5f;
    u.radius = m_frame.radius > 0 ? m_frame.radius : 0.4f * std::min(w, h);
    u.dpr = window() ? float(window()->effectiveDevicePixelRatio()) : 1.0f;
    colorToVec4(m_oceanColor, u.ocean);
    colorToVec4(m_oceanEdgeColor, u.edge);
    colorToVec4(m_glowColor, u.glow);
    u.glowWidth = std::clamp(u.radius * 0.07f, 6.0f, 48.0f);
    if (std::memcmp(&sm->u, &u, sizeof(u)) != 0) {
        sm->u = u;
        root->sphere.markDirty(QSGNode::DirtyMaterial);
    }

    // shapes: copy this frame's batch straight from the engine
    QSGGeometry *g = root->shapes.geometry();
    const int nv = int(m_frame.vertex_count), ni = int(m_frame.index_count);
    g->allocate(nv, ni);
    if (nv > 0 && ni > 0) {
        std::memcpy(g->vertexData(), m_frame.vertices, size_t(nv) * sizeof(KgVertex));
        std::memcpy(g->indexData(), m_frame.indices, size_t(ni) * sizeof(uint32_t));
    }
    root->shapes.markDirty(QSGNode::DirtyGeometry);
    return root;
}

void GlobeItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) {
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        pushViewport();
        requestFrame();
    }
}

void GlobeItem::itemChange(ItemChange change, const ItemChangeData &value) {
    QQuickItem::itemChange(change, value);
    switch (change) {
    case ItemVisibleHasChanged:
    case ItemSceneChange:
        if (isVisible() && window())
            requestFrame();
        else
            m_ticker->stop();
        break;
    case ItemDevicePixelRatioHasChanged:
        requestFrame();
        break;
    default:
        break;
    }
}

// ── camera API ───────────────────────────────────────────────────────────────

void GlobeItem::flyTo(double lat, double lon, double km) {
    const double r = km > 0 ? kg_globe_radius_for_km(m_globe, km) : 0.0;
    kg_globe_fly_to(m_globe, lat, lon, r);
    requestFrame();
}

void GlobeItem::zoomBy(double factor, double x, double y) {
    kg_globe_zoom_by(m_globe, factor, x, y, true);
    requestFrame();
}

void GlobeItem::zoomIn() { zoomBy(2.0, width() / 2, height() / 2); }
void GlobeItem::zoomOut() { zoomBy(0.5, width() / 2, height() / 2); }

void GlobeItem::resetView() {
    kg_globe_reset(m_globe);
    requestFrame();
}

QVariantMap GlobeItem::project(double lat, double lon) {
    double x = 0, y = 0;
    const double d = kg_globe_project(m_globe, lat, lon, &x, &y);
    return {{QStringLiteral("x"), x}, {QStringLiteral("y"), y},
            {QStringLiteral("visible"), d > 0.05}, {QStringLiteral("depth"), d}};
}

QVariantList GlobeItem::clusterMembers(int cluster) {
    QVariantList out;
    size_t n = 0;
    const uint32_t *idx = kg_globe_pin_members(m_globe, uint32_t(std::max(0, cluster)), &n);
    for (size_t i = 0; i < n; ++i)
        out.append(m_locations.value(int(idx[i])));
    return out;
}

QVariantMap GlobeItem::clusterInfo(int cluster) {
    double lat = 0, lon = 0;
    uint32_t weight = 0, lead = 0;
    if (cluster < 0 || !kg_globe_cluster_info(m_globe, uint32_t(cluster), &lat, &lon, &weight, &lead))
        return {};
    return {{QStringLiteral("lat"), lat}, {QStringLiteral("lon"), lon},
            {QStringLiteral("count"), int(weight)}, {QStringLiteral("lead"), int(lead)}};
}

void GlobeItem::expandCluster(int cluster) {
    const QVariantMap info = clusterInfo(cluster);
    if (info.isEmpty())
        return;
    // Members merge when closer than ~pin size; zooming 3× usually splits them.
    const double r = std::max(m_cam.radius * 3.0, m_cam.fit_radius * 2.0);
    kg_globe_fly_to(m_globe, info.value("lat").toDouble(), info.value("lon").toDouble(), r);
    requestFrame();
}

QString GlobeItem::placeName(double lat, double lon, double maxKm) const {
    if (!m_world)
        return {};
    char buf[256];
    const size_t n = kg_world_place_name(m_world, lat, lon, maxKm,
                                         reinterpret_cast<uint8_t *>(buf), sizeof buf, nullptr);
    return QString::fromUtf8(buf, qsizetype(n));
}

QVariantMap GlobeItem::placeInfo(double lat, double lon, double maxKm) const {
    if (!m_world)
        return {};
    char buf[256];
    double km = 0;
    const size_t n = kg_world_place_name(m_world, lat, lon, maxKm,
                                         reinterpret_cast<uint8_t *>(buf), sizeof buf, &km);
    if (n == 0)
        return {};
    return {{QStringLiteral("name"), QString::fromUtf8(buf, qsizetype(n))}, {QStringLiteral("km"), km}};
}

// ── input ────────────────────────────────────────────────────────────────────

void GlobeItem::setHovered(int cluster) {
    if (cluster == m_hovered)
        return;
    m_hovered = cluster;
    emit hoveredClusterChanged();
}

void GlobeItem::mousePressEvent(QMouseEvent *e) {
    forceActiveFocus(Qt::MouseFocusReason);
    m_pressed = true;
    m_dragging = false;
    m_pressPos = m_lastPos = e->position();
    m_samples.clear();
    m_samples.push_back({e->position(), m_inputClock.elapsed()});
    kg_globe_drag_begin(m_globe);
    emit interactionStarted();
    e->accept();
}

void GlobeItem::mouseMoveEvent(QMouseEvent *e) {
    if (!m_pressed)
        return;
    const QPointF p = e->position();
    if (!m_dragging && (p - m_pressPos).manhattanLength() > 4) {
        m_dragging = true;
        setCursor(Qt::ClosedHandCursor);
        setKeepMouseGrab(true);
    }
    if (m_dragging) {
        const QPointF d = p - m_lastPos;
        kg_globe_drag(m_globe, d.x(), d.y());
        requestFrame();
    }
    m_lastPos = p;
    const qint64 now = m_inputClock.elapsed();
    m_samples.push_back({p, now});
    while (m_samples.size() > 2 && now - m_samples.front().t > 90)
        m_samples.pop_front();
}

void GlobeItem::mouseReleaseEvent(QMouseEvent *e) {
    if (!m_pressed)
        return;
    m_pressed = false;
    setKeepMouseGrab(false);
    double vx = 0, vy = 0;
    if (m_dragging && m_samples.size() >= 2) {
        const qint64 now = m_inputClock.elapsed();
        const Sample &a = m_samples.front();
        const Sample &b = m_samples.back();
        const double dt = (b.t - a.t) / 1000.0;
        // only fling if the pointer was still moving at release
        if (dt > 0.008 && now - b.t < 60) {
            vx = (b.pos.x() - a.pos.x()) / dt;
            vy = (b.pos.y() - a.pos.y()) / dt;
        }
    }
    kg_globe_drag_end(m_globe, vx, vy);
    if (!m_dragging) {
        const QPointF p = e->position();
        const qint64 pin = kg_globe_pin_at(m_globe, p.x(), p.y());
        if (pin >= 0) {
            emit pinClicked(int(pin));
        } else {
            double lat = 0, lon = 0;
            if (kg_globe_unproject(m_globe, p.x(), p.y(), &lat, &lon))
                emit globeClicked(lat, lon);
        }
    }
    m_dragging = false;
    setCursor(m_hovered >= 0 ? Qt::PointingHandCursor : Qt::OpenHandCursor);
    requestFrame();
}

void GlobeItem::mouseDoubleClickEvent(QMouseEvent *e) {
    if (kg_globe_pin_at(m_globe, e->position().x(), e->position().y()) >= 0)
        return;
    const double f = (e->modifiers() & Qt::ShiftModifier) ? 0.4 : 2.5;
    zoomBy(f, e->position().x(), e->position().y());
}

void GlobeItem::hoverMoveEvent(QHoverEvent *e) {
    const QPointF p = e->position();
    const qint64 pin = kg_globe_pin_at(m_globe, p.x(), p.y());
    setHovered(int(pin));
    double lat, lon;
    const bool onGlobe = kg_globe_unproject(m_globe, p.x(), p.y(), &lat, &lon);
    setCursor(pin >= 0 ? Qt::PointingHandCursor : (onGlobe ? Qt::OpenHandCursor : Qt::ArrowCursor));
}

void GlobeItem::hoverLeaveEvent(QHoverEvent *) {
    setHovered(-1);
}

void GlobeItem::wheelEvent(QWheelEvent *e) {
    double steps;
    if (!e->pixelDelta().isNull())
        steps = e->pixelDelta().y() / 160.0; // touchpads: fine-grained
    else
        steps = e->angleDelta().y() / 120.0;
    if (steps == 0) {
        e->ignore();
        return;
    }
    kg_globe_zoom_by(m_globe, std::pow(2.0, steps * 0.45), e->position().x(), e->position().y(), true);
    emit interactionStarted();
    requestFrame();
    e->accept();
}

void GlobeItem::keyPressEvent(QKeyEvent *e) {
    const double step = 70;
    switch (e->key()) {
    case Qt::Key_Left:  kg_globe_drag_begin(m_globe); kg_globe_drag(m_globe, step, 0); kg_globe_drag_end(m_globe, 0, 0); break;
    case Qt::Key_Right: kg_globe_drag_begin(m_globe); kg_globe_drag(m_globe, -step, 0); kg_globe_drag_end(m_globe, 0, 0); break;
    case Qt::Key_Up:    kg_globe_drag_begin(m_globe); kg_globe_drag(m_globe, 0, step); kg_globe_drag_end(m_globe, 0, 0); break;
    case Qt::Key_Down:  kg_globe_drag_begin(m_globe); kg_globe_drag(m_globe, 0, -step); kg_globe_drag_end(m_globe, 0, 0); break;
    case Qt::Key_Plus:
    case Qt::Key_Equal: zoomIn(); break;
    case Qt::Key_Minus: zoomOut(); break;
    case Qt::Key_Home:
    case Qt::Key_0:     resetView(); break;
    default:
        e->ignore();
        return;
    }
    requestFrame();
    e->accept();
}

void GlobeItem::touchEvent(QTouchEvent *e) {
    const auto &pts = e->points();
    if (pts.size() == 2) {
        // pinch to zoom around the midpoint
        const QPointF a = pts[0].position(), b = pts[1].position();
        const QPointF pa = pts[0].lastPosition(), pb = pts[1].lastPosition();
        const double d1 = QLineF(a, b).length(), d0 = QLineF(pa, pb).length();
        if (d0 > 1 && d1 > 1) {
            const QPointF mid = (a + b) / 2, pmid = (pa + pb) / 2;
            kg_globe_drag(m_globe, mid.x() - pmid.x(), mid.y() - pmid.y());
            kg_globe_zoom_by(m_globe, d1 / d0, mid.x(), mid.y(), false);
            requestFrame();
        }
        e->accept();
        return;
    }
    // single finger: Qt synthesises mouse events
    e->ignore();
}
