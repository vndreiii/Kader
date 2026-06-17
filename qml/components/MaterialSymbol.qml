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
    
    text: name
    font.family: materialSymbolsFont.name
    font.pixelSize: root.size
    
    // Fallback if font weight or variable axes isn't perfectly supported in the QML version
    font.weight: Font.Normal + (Font.DemiBold - Font.Normal) * root.truncatedFill
    
    font.styleName: "Regular" // Often needed to reset custom font styles
    
    // Feed the fill value directly into the font renderer!
    // Requires Qt 6.7+ for variableAxes, but we can safely specify it.
    font.variableAxes: { "FILL": root.truncatedFill }
    
    width: implicitWidth
    height: implicitHeight
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter

    // Intercept instant changes to `fill` and animate them over 200ms
    Behavior on fill { 
        NumberAnimation {
            duration: ThemeManager.durShort
            easing.type: Easing.BezierSpline
        }
    }
}
