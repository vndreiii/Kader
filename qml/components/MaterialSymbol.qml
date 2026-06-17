import QtQuick
import ".."

Text {
    id: root
    property string name: ""
    property real size: 24
    
    // The raw fill target (0 or 1)
    property real fill: 0 
    
    // Optimization: Round it to 1 decimal place (0.0, 0.1 ... 1.0)
    property real truncatedFill: Number(fill.toFixed(1))
    
    FontLoader {
        id: msFont
        source: "qrc:/Kader/assets/MaterialSymbolsRounded.ttf"
    }
    
    text: name
    font.family: msFont.name
    font.pixelSize: root.size
    
    font.weight: Font.Normal
    renderType: Text.QtRendering
    
    // Feed the fill value directly into the font renderer!
    font.variableAxes: { "FILL": root.truncatedFill }
    
    width: implicitWidth
    height: implicitHeight
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
