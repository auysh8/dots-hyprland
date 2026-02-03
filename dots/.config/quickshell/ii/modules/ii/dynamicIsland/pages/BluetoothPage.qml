import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import Quickshell
import qs.modules.common
import qs.modules.common.widgets

Item {
   id: root
   
   // We use the first device roughly
   property var device: islandContainer.bluetoothDevices.length > 0 ? islandContainer.bluetoothDevices[0] : {name: "Unknown", battery: 0}
   
   RowLayout {
       anchors.fill: parent
       anchors.margins: 4
       spacing: 12
       
       // Headphone Icon
       MaterialSymbol {
           text: "headphones"
           iconSize: 32
           color: Appearance.colors.colPrimary
       }
       
       // Info
       ColumnLayout {
           Layout.fillWidth: true
           spacing: 0
           
           Text {
               Layout.fillWidth: true
               text: root.device.name
               font.pixelSize: 14
               font.weight: Font.Bold
               color: Appearance.colors.colOnLayer0
               elide: Text.ElideRight
           }
           
           Text {
               Layout.fillWidth: true
               text: "Connected"
               font.pixelSize: 12
               color: Appearance.colors.colOnLayer0
               opacity: 0.7
           }
       }
       
       // Battery Pill
       RowLayout {
           spacing: 4
           
           MaterialSymbol {
               text: {
                   var p = root.device.battery / 100;
                   if (p >= 0.9) return "battery_full";
                   if (p >= 0.6) return "battery_5_bar"; // approximated
                   if (p >= 0.4) return "battery_3_bar"; 
                   return "battery_alert";
               }
               iconSize: 16
               color: root.device.battery > 20 ? Appearance.colors.colSuccess : Appearance.colors.colError
           }
           
           Text {
               text: root.device.battery + "%"
               font.pixelSize: 16
               font.weight: Font.Bold
               color: Appearance.colors.colOnLayer0
           }
       }
   }
}
