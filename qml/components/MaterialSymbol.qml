import QtQuick
import ".."

Text {
    id: root
    property string name: ""
    property real size: 24
    
    // The raw fill target (0 or 1)
    property real fill: 0
    
    FontLoader {
        id: msFont
        source: "qrc:/Kader/assets/MaterialSymbolsRounded.ttf"
    }
    
    text: name
    font.family: msFont.name
    font.pixelSize: root.size
    
    font.weight: Font.Normal
    renderType: Text.NativeRendering
    
    // Feed the fill value directly into the font renderer!
    font.variableAxes: { "FILL": root.fill }
    
    width: implicitWidth
    height: root.size
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter

    // Intercept instant changes to `fill` and animate them over 200ms
    Behavior on fill { 
        NumberAnimation {
            duration: ThemeManager.durShort
            easing.type: Easing.OutCubic
        }
    }
}
