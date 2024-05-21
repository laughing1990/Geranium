//
//  LocSimView.swift
//  Geranium
//
//  Created by cclerc on 21.12.23.
//

import SwiftUI
import CoreLocation
import AlertKit
import Foundation

struct LocSimView: View {
    @StateObject private var appSettings = AppSettings()
    
    @State private var locationManager = CLLocationManager()
    @State private var lat: Double = 0.0
    @State private var long: Double = 0.0
    @State private var tappedCoordinate: EquatableCoordinate? = nil
    @State private var bookmarkSheetTggle: Bool = false
    @State private var appliedCust: Bool = false
    @State private var latTemp = ""
    @State private var longTemp = ""
    var body: some View {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    LocSimMainView()
                }
            } else {
                NavigationView {
                    LocSimMainView()
                }
            }
        }
    @ViewBuilder
        private func LocSimMainView() -> some View {
            VStack {
                CustomMapView(tappedCoordinate: $tappedCoordinate)
                    .onAppear {
                        CLLocationManager().requestAlwaysAuthorization()
                    }
            }
            .ignoresSafeArea(.keyboard)
        .onAppear {
            LocationModel().requestAuthorisation()
        }
        .onChange(of: tappedCoordinate) { newValue in
            if let coordinate = newValue {
                lat = coordinate.coordinate.latitude
                long = coordinate.coordinate.longitude
                let (newlatitude, newlongitude) = LocationTransform.gcj2wgs(wgsLat: lat, wgsLng: long)
                LocSimManager.startLocSim(location: .init(latitude: newlatitude, longitude: newlongitude))
                AlertKitAPI.present(
                    title: "Started !",
                    icon: .done,
                    style: .iOS17AppleMusic,
                    haptic: .success
                )
            }
        }
        .toolbar{
            ToolbarItem(placement: .navigationBarLeading) {
                Text("LocSim")
                    .font(.title2)
                    .bold()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    appliedCust.toggle()
                }) {
                    Image(systemName: "mappin")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    if appSettings.locSimMultipleAttempts {
                        var countdown = appSettings.locSimAttemptNB
                        DispatchQueue.global().async {
                            while countdown > 0 {
                                LocSimManager.stopLocSim()
                                countdown -= 1
                            }
                        }
                    }
                    else {
                        LocSimManager.stopLocSim()
                    }
                    AlertKitAPI.present(
                        title: "Stopped !",
                        icon: .done,
                        style: .iOS17AppleMusic,
                        haptic: .success
                    )
                }) {
                    Image(systemName: "location.slash")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    bookmarkSheetTggle.toggle()
                }) {
                    Image(systemName: "bookmark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
            }
        }
        .alert("Enter your coordinates", isPresented: $appliedCust) {
            TextField("Latitude", text: $latTemp)
            TextField("Longitude", text: $longTemp)
            Button("OK", action: submit)
        } message: {
            Text("The location will be simulated on device\nPro tip: Press wherever on the map to move there.")
        }
        .sheet(isPresented: $bookmarkSheetTggle) {
            BookMarkSlider(lat: $lat, long: $long)
        }
    }
    func submit() {
        if !latTemp.isEmpty, !longTemp.isEmpty {
            LocSimManager.startLocSim(location: .init(latitude: Double(latTemp) ?? 0.0, longitude: Double(longTemp) ?? 0.0))
        }
        else {
            UIApplication.shared.alert(body: "Those are empty coordinates mate !")
        }
    }
}

/**
 *  Struct transform coordinate between earth(WGS-84) and mars in china(GCJ-02).
 */
public struct LocationTransform {

    static let EARTH_R: Double = 6378137.0

    static func isOutOfChina(lat: Double, lng: Double) -> Bool {

        if lng < 72.004 || lng > 137.8347 {
            return true
        }
        if lat < 0.8293 || lat > 55.8271 {
            return true
        }
        return false
    }

    static func transform(x: Double, y: Double) -> (lat: Double, lng: Double) {

        let xy = x * y
        let absX = sqrt(fabs(x))
        let xPi = x * Double.pi
        let yPi = y * Double.pi
        let d = 20.0 * sin(6.0 * xPi) + 20.0 * sin(2.0 * xPi)

        var lat = d
        var lng = d

        lat += 20.0 * sin(yPi) + 40.0 * sin(yPi / 3.0)
        lng += 20.0 * sin(xPi) + 40.0 * sin(xPi / 3.0)

        lat += 160.0 * sin(yPi / 12.0) + 320 * sin(yPi / 30.0)
        lng += 150.0 * sin(xPi / 12.0) + 300 * sin(xPi / 30.0)

        lat *= 2.0 / 3.0
        lng *= 2.0 / 3.0

        lat += -100 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * xy + 0.2 * absX
        lng += 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * xy + 0.1 * absX

        return (lat, lng)
    }

    static func delta(lat: Double, lng: Double) -> (dLat: Double,  dLng: Double) {
        let ee = 0.00669342162296594323
        let radLat = lat / 180.0 * Double.pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        var (dLat, dLng) = transform(x: lng - 105.0, y: lat - 35.0)
        dLat = (dLat * 180.0) / ((EARTH_R * (1 - ee)) / (magic * sqrtMagic) * Double.pi)
        dLng = (dLng * 180.0) / (EARTH_R / sqrtMagic * cos(radLat) * Double.pi)
        return (dLat, dLng)
    }

    /**
     *  wgs2gcj convert WGS-84 coordinate(wgsLat, wgsLng) to GCJ-02 coordinate(gcjLat, gcjLng).
     *  wgs2gcj 将 WGS-84 坐标（wgsLat，wgsLng）转换为 GCJ-02 坐标（gcjLat，gcjLng）。
     */
    public static func wgs2gcj(wgsLat: Double, wgsLng: Double) -> (gcjLat: Double, gcjLng: Double) {
        if isOutOfChina(lat: wgsLat, lng: wgsLng) {
            return (wgsLat, wgsLng)
        }
        let (dLat, dLng) = delta(lat: wgsLat, lng: wgsLng)
        return (wgsLat + dLat, wgsLng + dLng)
    }

    /**
     *  gcj2wgs convert GCJ-02 coordinate(gcjLat, gcjLng) to WGS-84 coordinate(wgsLat, wgsLng).
     *  The output WGS-84 coordinate's accuracy is 1m to 2m. If you want more exactly result, use gcj2wgs_exact.
     *   gcj2wgs 将 GCJ-02 坐标（gcjLat，gcjLng）转换为 WGS-84 坐标（wgsLat，wgsLng）。
     *   输出WGS-84坐标的精度为1m至2m。 如果您想要更准确的结果，请使用 gcj2wgs_exact。
     */
    public static func gcj2wgs(gcjLat: Double, gcjLng: Double) -> (wgsLat: Double, wgsLng: Double) {
        if isOutOfChina(lat: gcjLat, lng: gcjLng) {
            return (gcjLat, gcjLng)
        }
        let (dLat, dLng) = delta(lat: gcjLat, lng: gcjLng)
        return (gcjLat - dLat, gcjLng - dLng)
    }

    /**
     *  gcj2wgs_exact convert GCJ-02 coordinate(gcjLat, gcjLng) to WGS-84 coordinate(wgsLat, wgsLng).
     *  The output WGS-84 coordinate's accuracy is less than 0.5m, but much slower than gcj2wgs.
     *   gcj2wgs_exact 将 GCJ-02 坐标（gcjLat，gcjLng）转换为 WGS-84 坐标（wgsLat，wgsLng）。
     *   输出的WGS-84坐标精度小于0.5m，但比gcj2wgs慢很多。
     */
    public static func gcj2wgs_exact(gcjLat: Double, gcjLng: Double) -> (wgsLat: Double, wgsLng: Double) {
        let initDelta = 0.01, threshold = 0.000001
        var (dLat, dLng) = (initDelta, initDelta)
        var (mLat, mLng) = (gcjLat - dLat, gcjLng - dLng)
        var (pLat, pLng) = (gcjLat + dLat, gcjLng + dLng)
        var (wgsLat, wgsLng) = (gcjLat, gcjLng)
        for _ in 0 ..< 30 {
            (wgsLat, wgsLng) = ((mLat + pLat) / 2, (mLng + pLng) / 2)
            let (tmpLat, tmpLng) = wgs2gcj(wgsLat: wgsLat, wgsLng: wgsLng)
            (dLat, dLng) = (tmpLat - gcjLat, tmpLng - gcjLng)
            if (fabs(dLat) < threshold) && (fabs(dLng) < threshold) {
                return (wgsLat, wgsLng)
            }
            if dLat > 0 {
                pLat = wgsLat
            } else {
                mLat = wgsLat
            }
            if dLng > 0 {
                pLng = wgsLng
            } else {
                mLng = wgsLng
            }
        }
        return (wgsLat, wgsLng)
    }

    /**
     *  Distance calculate the distance between point(latA, lngA) and point(latB, lngB), unit in meter.
     *  距离计算点（latA，lngA）和点（latB，lngB）之间的距离，单位为米。
     */
    public static func Distance(latA: Double, lngA: Double, latB: Double, lngB: Double) -> Double {
        let arcLatA = latA * Double.pi / 180
        let arcLatB = latB * Double.pi / 180
        let x = cos(arcLatA) * cos(arcLatB) * cos((lngA-lngB) * Double.pi/180)
        let y = sin(arcLatA) * sin(arcLatB)
        var s = x + y
        if s > 1 {
            s = 1
        }
        if s < -1 {
            s = -1
        }
        let alpha = acos(s)
        let distance = alpha * EARTH_R
        return distance
    }
}

extension LocationTransform {

    public static func gcj2bd(gcjLat: Double, gcjLng: Double) -> (bdLat: Double, bdLng: Double) {
        if isOutOfChina(lat: gcjLat, lng: gcjLng) {
            return (gcjLat, gcjLng)
        }
        let x = gcjLng, y = gcjLat
        let z = sqrt(x * x + y * y) + 0.00002 * sin(y * Double.pi)
        let theta = atan2(y, x) + 0.000003 * cos(x * Double.pi)
        let bdLng = z * cos(theta) + 0.0065
        let bdLat = z * sin(theta) + 0.006
        return (bdLat, bdLng)
    }

    public static func bd2gcj(bdLat: Double, bdLng: Double) -> (gcjLat: Double, gcjLng: Double) {
        if isOutOfChina(lat: bdLat, lng: bdLng) {
            return (bdLat, bdLng)
        }
        let x = bdLng - 0.0065, y = bdLat - 0.006
        let z = sqrt(x * x + y * y) - 0.00002 * sin(y * Double.pi)
        let theta = atan2(y, x) - 0.000003 * cos(x * Double.pi)
        let gcjLng = z * cos(theta)
        let gcjLat = z * sin(theta)
        return (gcjLat, gcjLng)
    }

    public static func wgs2bd(wgsLat: Double, wgsLng: Double) -> (bdLat: Double, bdLng: Double) {
        let (gcjLat, gcjLng) = wgs2gcj(wgsLat: wgsLat, wgsLng: wgsLng)
        return gcj2bd(gcjLat: gcjLat, gcjLng: gcjLng)
    }

    public static func bd2wgs(bdLat: Double, bdLng: Double) -> (wgsLat: Double, wgsLng: Double) {
        let (gcjLat, gcjLng) = bd2gcj(bdLat: bdLat, bdLng: bdLng)
        return gcj2wgs(gcjLat: gcjLat, gcjLng: gcjLng)
    }
}
