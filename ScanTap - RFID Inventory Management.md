**ScanTap \- RFID Inventory Management**  

1) Summary of new Application


* This is a new application on the Grotap Brand platform only  
* Name of App is : ScanTap  
* It is a platform application that Also has a sister Android Native app for Tablets and Phones  
* The Sister Native App, shows also on Platform as a Mobile Icon with ScanTap over it  
* When users click on Sister Native Android App, it opens the sister native app on your android or it gives you where to download the beta app or live app from the store  
* The sister mobile app \- ScanTap mobile, also has cobrowse built into it, so they can do all the same functionality we have for the platform app  
* The web application and mobile application are use the same cloud database in Neon  
    
2) Web Application Functionality

1) Screen Name: Print Tags  
   1) Printing Tags based on Receiving transactions already created in Customers Inventory Software  
   2) Printing Tags based on quantities entered in per inventory item on inventory screen  
2) Screen Name: Review & Apply Scans  
   1) Screen starts at batch level  
   2) Each time a user goes out and does a scan on an RFID reader using the mobile scantap app, when they return they sync the scans to the cloud  
   3) The scans show as a new batch on the review and apply screen  
   4) The batch shows the following columns: created date, \# of tags scanned, \# of unique products scanned, \# of locations scanned  
   5) A user can double click on the batch and it drills into the detail of that scan, it shows the total Quantity as the now by product ID scanned, Product ID, Description, size, category, type, Item Class, Income Account, Cost Account, Asset Account, Catalog ID, Customer Name ( can be null)  
   6) A user can export any one of the grid views to Excel or csv  
   7) A user can double click on the Product ID level and it will drill down into the rfid tag level data grid showing these columns : RFid tag, and all of the info from line E above.  
   8) If we scanned once per day, the last 3 days \- so 3 separate scans, it would show 3 batches when you first open review and apply  
   9) At any of the levels, batch, product id, tag level \- the user can hit a button on top : Compare to my Inventory \- and AI will run a comparison between the scan data and their inventory count.  It will come back with several reports and a suggested update to be applied to their inventory system.  
   10) Users can also use a check all button, after filtering on any column and once lines are checked off \- a pallet appears labeled: Update \- users can delete, set back as new for status, Set as Archived status  
   11) A user can check off a batch and if that batch has a customer name and customer ID associate ed with it, they can click Create Order or Create Invoice.  
   12) The customer data will sync from their other software to the RFID package, so that users can pick a customer before scanning when they want to scan an invoice  
   13) On the review screen, if they check off a batch that has customer on it, they can create order or create invoice.

3) Screen Name: Locations
   1) Web-app screen listing every physical inventory location for the business (warehouses, yards, fields, props), one row per location.
   2) Grid columns, in order: **Location Name**, **Zone Name**, **Site Name**, then **GeoLocation Point 1 … GeoLocation Point 25** (up to 25 geo points per location). Additional detail columns available/expandable: Type, Department, Address/City/State/Zip, Cost Account, Sales Account, Directions, Notes, Active.
   3) Each GeoLocation Point holds a captured GPS coordinate (lat/lng). They start **empty** and are filled in by the mobile geo-mapping/scan flow — when a scan is strongest near a location, that geo point is recorded against the location so future scans auto-reconcile to it (see "Location tricks" note). A location can map an area with up to 25 boundary/anchor points.
   4) Users can add/edit/delete locations, and export the grid to Excel/CSV (same pattern as Review & Apply).
   5) Locations are tenant-scoped; the initial Manorview Farms tenant is seeded from the SBI `tblICWarehouse` export (514 locations).
   6) **Import field mapping (SBI `tblICWarehouse` → ScanTap Locations):**

      | ScanTap field | Source column | Notes |
      |---|---|---|
      | Location Name | `strWarehouseID` | Always present; canonical name |
      | Description | `strDescription` | Friendly label (blank on ~40 rows) |
      | Zone Name | `strDivision` | Mostly blank in current data |
      | Site Name | `strSite` | Yard / Field / Prop / Maintenance |
      | Type | `strWarehouseType` | off site / off prem |
      | Department | `strDepartment` | YD / FD / PR / MT |
      | Address / City / State / Zip / County / Country | `strAddress` / `strCity` / `strState` / `strZip` / `strCounty` / `strCountry` | |
      | Cost Account | `strAccountCOGS` | |
      | Sales Account | `strAccountSales` | |
      | Directions | `strDirections` | (= "Location Explanation" in cleaned export) |
      | Notes | `strNotes` | |
      | Sort order | `lngSort` | |
      | Active | `ysnActive` | 1 → true |
      | Source id | `cntID` | origin row id for traceability |
      | GeoLocation Point 1–25 | — | Not in source; captured later via mobile |

       

4\) Native Android App Functionality

1) Menu 1 : Start Scanning New Batch  
2) When user opens this screen, it prompts \- start scanning now?  
3) No tags will be captured onto the device, until user clicks yes  
4) Once the scan begins, the Screen shows the following  
   1) Live scan of what reader is scanning  
   2) Sum of total tags scanned  
   3) Sum of total product IDs scanned  
   4) Sum of total Locations scanned  
   5) Current Geo-Location GPS that is being recorded with each scan  
   6) Distance traveled during the scan  
   7) Time of scan, stop watching is running  
   8) \# of tags scanned a minute  
5) Menu 2 : Setup \- on this screen the user sets up the connections to the reader.  See the specs on this reader and design the code and connection based on using the ( type connection )  
6) Plugs directly into the RFID reader and displays live what is being read on a screen so that users know what is happening and can confirm proper reading  
7) that shows sums of total read, last read in last 10 seconds, shows Geolocation that is being assigned at time of current reads, and shows location it associates with those geolocations.    
8) As tag data is captured, we want to save it to the tablet or to data on the scan device that saves the GEO location of when the scan was strongest for that tag  
9) We are trying to auto-assign a location based on Geo-code and we will save that geo-code with our tag data we pull off of the rfid reader.  
10) The process is they will hit start scan, they see as device scans and at end of scan, they can hit on scan screen \- Capture Scans to Tablet  
11) Scan data will then sync to native android app on the tablet  
12) When the user takes the tablet back to the office and gets an internet connection, they can go to Menu item : Send Scans to the Cloud  
13) Users can see batches of scans there and can check them off and when they hit \- Send to Cloud it will sync the scan data from the device to the Neon database.   
14) Users can then open the ScanTap app in platform and see a new batch of scans

4\) Key Logic for Native App to include

1) write the logic to **prevent the Android screen from dimming/sleeping** during long inventory cycles  
2)  implement a **SQLite database script** to save scanned tag records directly on the local tablet storage  
3) configure **audio beep effects** via the tablet speaker whenever

   

5\) RFID Reader Hardware specifications for writing code on Native Android App to connect to device and capture data from scans using USB Connection from android tablet

Must use USB connection so we dont need wifi or ethernet connection  
We want plug and play, or bluetooth and go

 To operate the **CSL CS463 Reader** via a direct USB connection to an Android tablet, your native app must use the **Android USB Host API**. Because the CS463 uses an internal USB-to-UART bridge, Android treats it as a serial device rather than a standard storage or network interface.  
---

## 📋 Android-Specific USB Integration Specs

* **Connection Mode:** Android USB Host Mode (The Android tablet acts as the Master/Host; the CS463 acts as the Peripheral/Slave).  
* **Physical Cabling:** You must use an **OTG (On-The-Go) Adapter** or a specialized **USB-C to USB-B cable** connected directly from the tablet to the CS463's USB Client port.  
* **Power Architecture:** The Android tablet **cannot** power the CS463. The reader must remain powered externally via its **12V DC power port**.  
* **Driver Layer:** You can skip writing a custom USB kernel driver by implementing the popular, open-source [usb-serial-for-android library](https://github.com/mik3y/usb-serial-for-android). This handles the low-level USB-to-Serial transaction layer for the reader's communication bridge (115200 baud, 8N1).

---

## 🛠️ Step 1: Configure Android Manifest and Permissions

Your app must request hardware-level permission to access connected USB peripherals.

Add these lines to your `AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://android.com" package="com.example.rfid_usb_capture">

    <!-- Declare that the app requires USB Host hardware capability -->
    <uses-feature android:name="android.hardware.usb.host" android:required="true" />

    <application ...>
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>

            <!-- Filters for automated connection when the reader is physically plugged in -->
            <intent-filter>
                <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" />
            </intent-filter>
            <meta-data android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" android:resource="@xml/device_filter" />
        </activity>
    </application>
</manifest>
```

Create a file named `device_filter.xml` inside your project's `res/xml/` directory to recognize the reader's Silicon Labs USB communication bridge automatically:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Silicon Labs CP210x USB to UART Bridge (Standard for CS463) -->
    <usb-device vendor-id="4292" product-id="60000" />
</resources>
```

---

## 💻 Step 2: Native Android Code (Kotlin)

This native Kotlin implementation searches for the connected USB device, requests permission from the user, opens a raw communication channel, transmits the **CSL Low-Level Byte Stream start command**, and reads incoming tags asynchronously.

Include the following implementation in your `MainActivity.kt`:

```kotlin
package com.example.rfid_usb_capture

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.os.Bundle
import android.util.Log
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import java.io.IOException
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {

    private val TAG = "CS463_USB"
    private val ACTION_USB_PERMISSION = "com.example.rfid_usb_capture.USB_PERMISSION"
    
    // CSL Low-Level Command Byte Sequences
    private val PREFIX_COMMAND = byteArrayOf(0xA7.toByte(), 0xB3.toByte())
    private val CMD_START_INVENTORY = byteArrayOf(0x01.toByte(), 0x02.toByte())
    private val REQ_TAIL = byteArrayOf(0x00.toByte())
    
    private var usbManager: UsbManager? = null
    private var serialPort: UsbSerialPort? = null
    private var usbConnection: UsbDeviceConnection? = null
    private var isReading = false
    private val executor = Executors.newSingleThreadExecutor()
    
    private lateinit var logTextView: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        logTextView = findViewById(R.id.logTextView) // Ensure you have a TextView with this ID in your layout
        
        usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        initUsbConnection()
    }

    private fun initUsbConnection() {
        val availableDrivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
        if (availableDrivers.isEmpty()) {
            updateLog("No USB Serial devices found. Check physical connection.")
            return
        }

        // Get the first matching device driver
        val driver = availableDrivers[0]
        val device = driver.device

        if (usbManager!!.hasPermission(device)) {
            startSerialCommunication(driver.ports[0], device)
        } else {
            val permissionIntent = PendingIntent.getBroadcast(this, 0, Intent(ACTION_USB_PERMISSION), PendingIntent.FLAG_IMMUTABLE)
            usbManager!!.requestPermission(device, permissionIntent)
            updateLog("Requesting USB peripheral access permission...")
        }
    }

    private fun startSerialCommunication(port: UsbSerialPort, device: UsbDevice) {
        usbConnection = usbManager!!.openDevice(device)
        if (usbConnection == null) {
            updateLog("Failed to open USB Device Connection hardware channel.")
            return
        }

        serialPort = port
        try {
            // Open the serial driver connection channel
            serialPort!!.open(usbConnection)
            // Configure to matching CSL reader serial parameters
            serialPort!!.setParameters(115200, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE)
            
            updateLog("USB Serial link initialized at 115200 baud.")
            
            // Trigger hardware read command
            startInventoryScan()
        } catch (e: IOException) {
            updateLog("Error setting up serial configurations: ${e.message}")
        }
    }

    private fun startInventoryScan() {
        if (serialPort == null) return
        try {
            // Construct command payload packet: Prefix + Length + Command + Checksum Tail
            val commandPacket = PREFIX_COMMAND + byteArrayOf(0x02.toByte()) + CMD_START_INVENTORY + REQ_TAIL
            serialPort!!.write(commandPacket, 1000)
            
            isReading = true
            executor.execute { readBufferLoop() }
            updateLog("RFID Scanning command broadcasted over physical wire...")
        } catch (e: IOException) {
            updateLog("Failed to write initialization commands: ${e.message}")
        }
    }

    private fun readBufferLoop() {
        val buffer = ByteArray(1024)
        while (isReading) {
            try {
                val numBytesRead = serialPort!!.read(buffer, 200)
                if (numBytesRead > 0) {
                    parseIncomingData(buffer.copyOfRange(0, numBytesRead))
                }
            } catch (e: IOException) {
                Log.e(TAG, "Buffer reading process disconnected.", e)
                isReading = false
            }
        }
    }

    private fun parseIncomingData(data: ByteArray) {
        // Look for CSL specific low-level system response headers: 0x5A, 0xC3
        if (data.size >= 6 && data[0] == 0x5A.toByte() && data[1] == 0xC3.toByte()) {
            val payloadLength = data[2].toInt()
            
            // Extract the EPC sub-array out of the raw response payload structure
            if (data.size >= payloadLength) {
                val epcBytes = data.copyOfRange(5, data.size - 1)
                val epcHexStr = epcBytes.joinToString("") { String.format("%02X", it) }
                
                runOnUiThread {
                    updateLog("[TAG DETECTED] EPC: $epcHexStr")
                }
            }
        }
    }

    private fun updateLog(message: String) {
        logTextView.append("\n$message")
        Log.d(TAG, message)
    }

    override fun onDestroy() {
        super.onDestroy()
        isReading = false
        try {
            serialPort?.close()
        } catch (e: IOException) {
            // Suppress cleanup closure errors
        }
    }
}
```

---

## ⚠️ Critical Requirements for Android USB Apps

1. **Explicit Android OTG Capability:** Verify that your chosen Android tablet explicitly supports **USB Host Mode / OTG** in its manufacturer specifications. Budget tablets occasionally omit this feature at the operating system kernel level.  
2. **Handle the OS Permission Prompt:** Android displays a mandatory system security pop-up requesting permission to access the USB device when plugged in. Your app must wait for the user to approve this dialog before it can open the input/output serial data streams.

---

Questions on this  
Can we read Voucher table live to print tags immediately after voucher created?  
Can we print tags before posted, or should we not ?  
We print tags, then they are scanned into inventory ? or at time of print put into inventory?

**Web Application & Android Native App: Adding inventory to the system / Planting new Items ( No production work order )**  
Pick items to plant in RFID software 

Enter how many tags to print of each item  
Pre-print the tags  
Tag to the field and scan as planted  
Scan as set down to new location

**Web Application & Android Native App: Adding inventory to the system / Planting new Items ( Production work order )**  
Open SBI Production Work order view, select the work order  
Pre-print RFID tags for production work order  
Tag and scan as planted in the field  
Scan as set down to new location

**Web Application & Android Native App:Dumping Inventory / Set Scan to dump**  
Set to scan to dump ( mobile app )  
Scan dumps  
Review and apply  
Or sync to web app to review and apply

**Android Native App: Scanning Inventory / Golf Cart Unit \- Drive Scan**  
Turn on Unit with Tablet / Screen Attached  
Drive the farm, watch total tags scanned, total by variety scanned as you scan the farm  
Sync scan from tablet to RFID cloud software  
Return to Office  
Open RFID web App and review scanned inventory  
Review scanned inventory compared to sbi current live inventory  
See DELTA and ha ve AI review it and point out issues to watch for  
AI proposes how to apply the count to update SBI to be live

**Functionality on RFID Web Application**  
View and update inventory  
AI review of Scans and Inventory for ‘dud” tags  
Reviewing of field scan counts and updating of SBI   
Print tags for SBI vouchers  
Print tags for SBI production work orders  
Print tags for planting in the field 

**Web Application: Viewing RFID Inventory in RFID Web Application**  
Summary view options:   
\-Description, size, Total in Stock  
\-Description, size, Location, Total in stock  
\-Description, size, location, ready date, total in stock  
\-Description, size, location, RFID Tag ID

**Functionality on RFID Mobile Application**  
\-Field Scans screen shows data being captures and has summary counts  
\-Gives user good data to have awareness things are working as they should  
\-Displays GEO coordinates being saved with the RFID read data to auto-reconcile location  
\-Uploads a new scan as a “batch” / Batches can be reviewed in RFID web application.

Note  
Location tricks, requires geo mapping of locations and if we have wifi geo location on, we can get within 1 foot of accuracy

