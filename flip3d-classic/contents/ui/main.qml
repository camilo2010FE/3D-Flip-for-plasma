    /*
 * Aero Flip 3D "Classic" - window switcher for KWin / Plasma 6.8.
 *
 * Same TabBox + PlasmaCore.Dialog scaffolding as the first prototype, but:
 *  - only real windows: live WindowThumbnail with its own proportions,
 *    no fake frame, title strip or glass card around it;
 *  - hand-written stack layout instead of a PathView, so each Tab is ONE
 *    continuous motion (no windows vanishing and reappearing along a path).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.kwin as KWin

KWin.TabBoxSwitcher {
    id: tabBox

    Instantiator {
        active: tabBox.visible

        delegate: PlasmaCore.Dialog {
            id: switcherDialog

            location: PlasmaCore.Types.Floating
            visible: true
            flags: Qt.ToolTip | Qt.X11BypassWindowManagerHint
            backgroundHints: PlasmaCore.Dialog.NoBackground

            x: tabBox.screenGeometry.x
            y: tabBox.screenGeometry.y

            mainItem: FocusScope {
                id: scene

                width: Math.max(1, tabBox.screenGeometry.width)
                height: Math.max(1, tabBox.screenGeometry.height)
                focus: true

                // ---------------- Ajustes de diseño (afinar aquí) ----------------
                readonly property real frontX: 0.60     // centro de la ventana frontal (fracción del ancho)
                readonly property real frontY: 0.58     // centro de la ventana frontal (fracción del alto)
                readonly property real stepX: 0.155     // desplazamiento por escalón hacia la izquierda
                readonly property real stepY: 0.075     // desplazamiento por escalón hacia arriba
                readonly property real backRatio: 0.2 // separación constante entre ventanas del fondo, relativa a la primera (1.0 = igual que la primera)
                readonly property real scaleStep: 0.90  // escala por escalón hacia atrás
                readonly property real yawFront: 20     // grados de giro de la ventana frontal
                readonly property real yawBack: 60      // grados de giro de las ventanas del fondo
                readonly property real yawRamp: 0.60    // <1: las ventanas del fondo llegan antes al giro máximo
                readonly property int maxVisible: 7     // ventanas visibles en la pila
                readonly property real maxW: 0.56       // ancho máximo de una ventana (fracción de pantalla)
                readonly property real maxH: 0.68       // alto máximo de una ventana (fracción de pantalla)
                readonly property real frontBoost: 1.00 // aumento SOLO de la ventana seleccionada (1.0 = sin aumento)
                readonly property real frontLift: 0.00  // sube un poco la ventana seleccionada (fracción del alto)
                readonly property bool keepScreenPosition: true // true: cada ventana conserva su posición y tamaño dentro de la pantalla (como Flip 3D); false: todas llenan su tarjeta
                readonly property int moveDuration: 280 // ms por paso
                // -----------------------------------------------------------------

                // targetPos es un índice "desenrollado" (puede pasar de count) para
                // que el movimiento siempre tome el camino más corto; position lo anima.
                property real targetPos: tabBox.currentIndex
                property real position: targetPos
                property int lastIndex: tabBox.currentIndex
                property string currentTitle: ""
                readonly property int count: stack.count

                Behavior on position {
                    NumberAnimation {
                        duration: scene.moveDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Connections {
                    target: tabBox

                    function onCurrentIndexChanged() {
                        const n = stack.count;
                        if (n < 1) {
                            return;
                        }
                        let d = tabBox.currentIndex - scene.lastIndex;
                        if (d > n / 2) {
                            d -= n;
                        } else if (d < -n / 2) {
                            d += n;
                        }
                        scene.lastIndex = tabBox.currentIndex;
                        scene.targetPos += d;
                    }
                }

                function step(dir) {
                    const n = stack.count;
                    if (n < 2) {
                        return;
                    }
                    tabBox.currentIndex = (tabBox.currentIndex + dir + n) % n;
                }

                Keys.onLeftPressed: step(-1)
                Keys.onRightPressed: step(1)
                Keys.onUpPressed: step(-1)
                Keys.onDownPressed: step(1)

                // Velo oscuro suave sobre el escritorio.
                Rectangle {
                    anchors.fill: parent
                    color: "#40102034"
                }

                Repeater {
                    id: stack
                    model: tabBox.model

                    delegate: Item {
                        id: card

                        readonly property bool selected: index === tabBox.currentIndex
                        readonly property string windowTitle: String(model.caption || "")

                        // Geometría real de la ventana en el escritorio (KWin la expone en thumb.client).
                        readonly property rect screenRect: tabBox.screenGeometry
                        readonly property var geo: (scene.keepScreenPosition && thumb.client) ? thumb.client.frameGeometry : null
                        readonly property bool hasGeo: geo !== null && geo !== undefined
                        && geo.width > 1 && geo.height > 1
                        && screenRect.width > 0 && screenRect.height > 0

                        // Con hasGeo, la tarjeta es un "marco" con la proporción de la pantalla y la
                        // ventana se coloca dentro según dónde está en el escritorio.
                        // Sin geometría, la tarjeta toma la proporción de la ventana (si aún no hay textura, 16:10).
                        readonly property real windowRatio: (thumb.implicitWidth > 0 && thumb.implicitHeight > 0)
                        ? thumb.implicitWidth / thumb.implicitHeight
                        : 1.6
                        readonly property real ratio: hasGeo ? screenRect.width / screenRect.height : windowRatio

                        readonly property real relW: hasGeo ? Math.min(1, geo.width / screenRect.width) : 1
                        readonly property real relH: hasGeo ? Math.min(1, geo.height / screenRect.height) : 1
                        // Si la ventana está en otra pantalla, se centra en el marco en vez de salirse.
                        readonly property bool onScreen: hasGeo
                        && geo.x + geo.width / 2 >= screenRect.x
                        && geo.x + geo.width / 2 <= screenRect.x + screenRect.width
                        && geo.y + geo.height / 2 >= screenRect.y
                        && geo.y + geo.height / 2 <= screenRect.y + screenRect.height
                        readonly property real relX: !hasGeo ? 0
                        : (onScreen ? Math.max(0, Math.min(1 - relW, (geo.x - screenRect.x) / screenRect.width))
                        : (1 - relW) / 2)
                        readonly property real relY: !hasGeo ? 0
                        : (onScreen ? Math.max(0, Math.min(1 - relH, (geo.y - screenRect.y) / screenRect.height))
                        : (1 - relH) / 2)

                        // Posición relativa en la pila: 0 = frente, 1 = siguiente...
                        // Valores negativos: la ventana avanza hacia el espectador al
                        // cambiar de selección y se desvanece mientras sale.
                        readonly property real rel: {
                            const n = Math.max(1, scene.count);
                            return (((index - scene.position + 0.5) % n) + n) % n - 0.5;
                        }
                        readonly property real ahead: Math.max(0, rel)
                        readonly property real out: Math.max(0, -rel)
                        readonly property real depth: Math.min(ahead, 1) + Math.max(0, ahead - 1) * scene.backRatio
                        readonly property real farLimit: Math.min(scene.count - 0.5, scene.maxVisible)
                        readonly property real cardOpacity: Math.max(0, Math.min(1, 1 - out * 2, (farLimit - rel) * 2))

                        width: Math.min(scene.width * scene.maxW, scene.height * scene.maxH * ratio)
                        height: width / ratio

                        x: scene.width * (scene.frontX - depth * scene.stepX + out * 0.10) - width / 2
                        y: scene.height * (scene.frontY - depth * scene.stepY + out * 0.06 - scene.frontLift * Math.max(0, 1 - ahead)) - height / 2
                        z: 1000 - rel * 10
                        scale: Math.pow(scene.scaleStep, ahead) * (1 + (scene.frontBoost - 1) * Math.max(0, 1 - ahead)) * (1 + out * 0.10)
                        opacity: cardOpacity
                        visible: cardOpacity > 0.01
                        enabled: cardOpacity > 0.6

                        transform: Rotation {
                            origin.x: card.width / 2
                            origin.y: card.height / 2
                            axis { x: 0; y: 1; z: 0 }
                            angle: scene.yawFront + (scene.yawBack - scene.yawFront) * (1 - Math.pow(scene.yawRamp, card.ahead))
                        }

                        // La ventana real, sin marcos ni decoraciones añadidas,
                        // colocada dentro del marco según su posición en la pantalla.
                        KWin.WindowThumbnail {
                            id: thumb
                            x: card.relX * card.width
                            y: card.relY * card.height
                            width: card.relW * card.width
                            height: card.relH * card.height
                            wId: windowId
                        }

                        MouseArea {
                            anchors.fill: thumb
                            onClicked: {
                                if (card.selected) {
                                    tabBox.model.activate(index);
                                    return;
                                }
                                tabBox.currentIndex = index;
                            }
                        }

                        Binding {
                            target: scene
                            property: "currentTitle"
                            value: card.windowTitle
                            when: card.selected
                        }
                    }
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                    onWheel: (event) => {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                        if (delta === 0) {
                            return;
                        }
                        scene.step(delta < 0 ? 1 : -1);
                        event.accepted = true;
                    }
                }

                // Título de la ventana seleccionada (fuera de las ventanas, sin rotar).
                Rectangle {
                    z: 2000
                    visible: scene.currentTitle !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: scene.width * 0.08
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Math.max(28, scene.height * 0.045)
                    width: Math.min(scene.width * 0.56, Math.max(240, currentTitleText.implicitWidth + 46))
                    height: 42
                    radius: 21
                    color: "#9B102A45"
                    border.width: 1
                    border.color: "#75D8F4FF"

                    Text {
                        id: currentTitleText
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: scene.currentTitle
                        color: "#F4FAFF"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
            }

            onSceneGraphError: () => {
                // Intencionalmente vacío: evita qFatal() ante un reinicio de gráficos.
            }
        }
    }
}
