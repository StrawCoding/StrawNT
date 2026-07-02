/* StrawWU Calamares install slideshow */
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation

    function nextSlide() {
        presentation.goToNextSlide();
    }

    Timer {
        id: advanceTimer
        interval: 2200
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0a0e14"
            Column {
                anchors.centerIn: parent
                spacing: 18
                Image {
                    source: "strawwu-logo-icon.png"
                    width: 128; height: 128
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "StrawWU"
                    color: "#f4f6f9"
                    font.pixelSize: 36
                    font.weight: Font.DemiBold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0a0e14"
            Column {
                anchors.centerIn: parent
                spacing: 16
                Text {
                    text: "StrawWU 安裝程式"
                    color: "#e8e8f0"
                    font.pixelSize: 28
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "正在準備您的系統，請稍候…"
                    color: "#9aa3b8"
                    font.pixelSize: 16
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0a0e14"
            Column {
                anchors.centerIn: parent
                spacing: 12
                Repeater {
                    model: ["硬體偵測", "分割區配置", "系統檔案複製", "開機載入器"]
                    Text {
                        text: "• " + modelData
                        color: "#14b8a6"
                        font.pixelSize: 18
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }

    function onActivate() {
        presentation.currentSlide = 0;
    }

    function onLeave() {
        advanceTimer.stop();
    }
}
