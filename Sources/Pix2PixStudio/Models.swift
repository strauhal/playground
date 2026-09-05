import Foundation
import SwiftUI

enum SidebarPage: String, CaseIterable, Identifiable {
    case studio = "Studio"
    case downloads = "Models & Data"
    case files = "Files"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .studio: return "wand.and.stars"
        case .downloads: return "square.and.arrow.down"
        case .files: return "folder"
        }
    }
}

enum Pix2PixPreset: String, CaseIterable, Identifiable {
    case handbags, shoes, facades, satelliteToMap, mapToSatellite, dayToNight, cats

    var id: String { rawValue }
    var title: String {
        switch self {
        case .handbags: return "Edges → Handbags"
        case .shoes: return "Edges → Shoes"
        case .facades: return "Labels → Facades"
        case .satelliteToMap: return "Satellite → Map"
        case .mapToSatellite: return "Map → Satellite"
        case .dayToNight: return "Day → Night"
        case .cats: return "Edges → Cats"
        }
    }
    var shortTitle: String {
        switch self {
        case .handbags: return "Handbags"
        case .shoes: return "Shoes"
        case .facades: return "Facades"
        case .satelliteToMap: return "Satellite to Map"
        case .mapToSatellite: return "Map to Satellite"
        case .dayToNight: return "Day to Night"
        case .cats: return "Cats"
        }
    }
    var symbol: String {
        switch self {
        case .handbags: return "handbag.fill"
        case .shoes: return "shoe.fill"
        case .facades: return "building.2.fill"
        case .satelliteToMap: return "map.fill"
        case .mapToSatellite: return "globe.americas.fill"
        case .dayToNight: return "moon.stars.fill"
        case .cats: return "cat.fill"
        }
    }
    var accent: Color {
        switch self {
        case .handbags: return .orange
        case .shoes: return .pink
        case .facades: return .blue
        case .satelliteToMap: return .green
        case .mapToSatellite: return .teal
        case .dayToNight: return .indigo
        case .cats: return .purple
        }
    }
    var engineLabel: String { self == .cats ? "Legacy TensorFlow · CPU" : "PyTorch · Metal (MPS)" }
    var modelSize: String { self == .cats ? "193 MB" : "208 MB" }
    var checkpointName: String {
        switch self {
        case .handbags: return "edges2handbags"
        case .shoes: return "edges2shoes"
        case .facades: return "facades_label2photo"
        case .satelliteToMap: return "sat2map"
        case .mapToSatellite: return "map2sat"
        case .dayToNight: return "day2night"
        case .cats: return "edges2cats"
        }
    }
    var mirrorFileID: String? {
        switch self {
        case .handbags: return "1Z7HM6ah3fzjmrc8E9LyHyM_4DYyWxhVC"
        case .shoes: return "1eoDb93oQddMgLP8SBdr9RYepvNcuwcRq"
        case .facades: return "1msyExQSJudWzDvWMSCP6BQdP8otygV2g"
        case .satelliteToMap: return "1VCtPyCI8FZCyGlKPV8WXE32I2ntvXoTM"
        case .mapToSatellite: return "1y1x13gwppa7hjzV9BEk7JEOeMRnJdVzz"
        case .dayToNight: return "1OrMXnCmfHswUuA63hr09yx_UFzelCHnx"
        case .cats: return nil
        }
    }
}

enum DatasetPackage: String, CaseIterable, Identifiable {
    case edges2handbags, edges2shoes, facades, maps, night2day, cityscapes, edges2cats

    var id: String { rawValue }
    var title: String {
        switch self {
        case .edges2handbags: return "Edges ↔ Handbags"
        case .edges2shoes: return "Edges ↔ Shoes"
        case .facades: return "Architectural Facades"
        case .maps: return "Aerial Photos ↔ Maps"
        case .night2day: return "Night ↔ Day"
        case .cityscapes: return "Cityscapes"
        case .edges2cats: return "Edges ↔ Cats"
        }
    }
    var size: String {
        switch self {
        case .edges2handbags: return "8.6 GB"
        case .edges2shoes: return "2.2 GB"
        case .facades: return "31 MB"
        case .maps: return "246 MB"
        case .night2day: return "~2 GB"
        case .cityscapes: return "113 MB"
        case .edges2cats: return "58 MB"
        }
    }
    var sourceName: String { self == .edges2cats ? "Community release" : "Official pix2pix dataset" }
}

struct SketchStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
}

enum ExportSize: Int, CaseIterable, Identifiable {
    case px256 = 256, px512 = 512, px1024 = 1024, px2048 = 2048
    var id: Int { rawValue }
    var label: String { "\(rawValue) px" }
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}
