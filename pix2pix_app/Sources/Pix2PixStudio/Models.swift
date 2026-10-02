import Foundation
import SwiftUI

enum SidebarPage: String, CaseIterable, Identifiable {
    case studio = "Studio"
    case nextFrame = "Next Frame"
    case styleGAN2 = "StyleGAN2"
    case downloads = "Models & Data"
    case files = "Files"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .studio: return "wand.and.stars"
        case .nextFrame: return "film.stack"
        case .styleGAN2: return "point.3.connected.trianglepath.dotted"
        case .downloads: return "square.and.arrow.down"
        case .files: return "folder"
        }
    }
}

enum StyleGANPreset: String, CaseIterable, Identifiable {
    case ffhq, metfaces, afhqcat, afhqdog, afhqwild, cifar10, brecahad

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ffhq: return "FFHQ · Human Faces"
        case .metfaces: return "MetFaces · Painted Faces"
        case .afhqcat: return "AFHQ · Cats"
        case .afhqdog: return "AFHQ · Dogs"
        case .afhqwild: return "AFHQ · Wild Animals"
        case .cifar10: return "CIFAR-10 · Objects"
        case .brecahad: return "BreCaHAD · Histology"
        }
    }
    var shortTitle: String {
        switch self {
        case .ffhq: return "FFHQ"
        case .metfaces: return "MetFaces"
        case .afhqcat: return "AFHQ Cat"
        case .afhqdog: return "AFHQ Dog"
        case .afhqwild: return "AFHQ Wild"
        case .cifar10: return "CIFAR-10"
        case .brecahad: return "BreCaHAD"
        }
    }
    var nativeResolution: Int {
        switch self {
        case .ffhq, .metfaces: return 1024
        case .afhqcat, .afhqdog, .afhqwild, .brecahad: return 512
        case .cifar10: return 32
        }
    }
    var modelSize: String {
        switch self {
        case .ffhq, .metfaces: return "382 MB"
        case .afhqcat, .afhqdog, .afhqwild, .brecahad: return "364 MB"
        case .cifar10: return "246 MB"
        }
    }
    var downloadURL: URL {
        URL(string: "https://nvlabs-fi-cdn.nvidia.com/stylegan2-ada-pytorch/pretrained/\(rawValue).pkl")!
    }
    var symbol: String {
        switch self {
        case .ffhq: return "person.crop.square"
        case .metfaces: return "paintpalette.fill"
        case .afhqcat: return "cat.fill"
        case .afhqdog, .afhqwild: return "pawprint.fill"
        case .cifar10: return "square.grid.3x3.fill"
        case .brecahad: return "circle.hexagongrid.fill"
        }
    }
}

enum StyleGANMode: String, CaseIterable, Identifiable {
    case latent = "Latent Journey"
    case video = "Project Video"
    case training = "Train from Videos"
    var id: String { rawValue }
}

enum StyleGANInterpolation: String, CaseIterable, Identifiable {
    case smooth = "Smooth"
    case linear = "Linear"
    case spherical = "Spherical"
    var id: String { rawValue }
}

enum StyleGANNoiseMode: String, CaseIterable, Identifiable {
    case constant = "Stable"
    case random = "Living"
    case none = "None"
    var id: String { rawValue }
    var backendValue: String { self == .constant ? "const" : rawValue }
}

enum StyleGANVideoFit: String, CaseIterable, Identifiable {
    case fit = "Fit Entire Frame"
    case crop = "Center Crop"
    case stretch = "Stretch"
    var id: String { rawValue }
    var backendValue: String {
        switch self { case .fit: return "fit"; case .crop: return "crop"; case .stretch: return "stretch" }
    }
}

enum StyleGANTrainingSize: Int, CaseIterable, Identifiable {
    case quick64 = 64
    case fast128 = 128
    case balanced256 = 256
    case detailed512 = 512
    case native = 0

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .quick64: return "Quick Sketch · 64 px"
        case .fast128: return "Fast Preview · 128 px"
        case .balanced256: return "Balanced · 256 px"
        case .detailed512: return "Detailed · 512 px"
        case .native: return "Original Resolution · Slowest"
        }
    }
}

enum Pix2PixPreset: String, CaseIterable, Identifiable {
    case handbags, shoes, facades, satelliteToMap, mapToSatellite, dayToNight, cats
    case appleToOrange, orangeToApple, summerToWinter, winterToSummer
    case horseToZebra, zebraToHorse, monetToPhoto
    case photoToMonet, photoToCezanne, photoToUkiyoe, photoToVanGogh
    case cycleSatelliteToMap, cycleMapToSatellite
    case cityPhotoToLabels, cityLabelsToPhoto
    case facadePhotoToLabels, facadeLabelsToPhoto
    case iphoneToDSLR

    static let pix2pixModels: [Self] = [.handbags, .shoes, .facades, .satelliteToMap, .mapToSatellite, .dayToNight, .cats]
    static let cycleGANModels: [Self] = [.appleToOrange, .orangeToApple, .summerToWinter, .winterToSummer,
        .horseToZebra, .zebraToHorse, .monetToPhoto, .photoToMonet, .photoToCezanne, .photoToUkiyoe,
        .photoToVanGogh, .cycleSatelliteToMap, .cycleMapToSatellite, .cityPhotoToLabels,
        .cityLabelsToPhoto, .facadePhotoToLabels, .facadeLabelsToPhoto, .iphoneToDSLR]

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
        case .appleToOrange: return "Apple → Orange"
        case .orangeToApple: return "Orange → Apple"
        case .summerToWinter: return "Summer → Winter"
        case .winterToSummer: return "Winter → Summer"
        case .horseToZebra: return "Horse → Zebra"
        case .zebraToHorse: return "Zebra → Horse"
        case .monetToPhoto: return "Monet → Photo"
        case .photoToMonet: return "Photo → Monet"
        case .photoToCezanne: return "Photo → Cézanne"
        case .photoToUkiyoe: return "Photo → Ukiyo-e"
        case .photoToVanGogh: return "Photo → Van Gogh"
        case .cycleSatelliteToMap: return "Satellite → Map"
        case .cycleMapToSatellite: return "Map → Satellite"
        case .cityPhotoToLabels: return "City Photo → Labels"
        case .cityLabelsToPhoto: return "City Labels → Photo"
        case .facadePhotoToLabels: return "Facade Photo → Labels"
        case .facadeLabelsToPhoto: return "Facade Labels → Photo"
        case .iphoneToDSLR: return "iPhone → DSLR Flowers"
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
        case .appleToOrange: return "Apple to Orange"
        case .orangeToApple: return "Orange to Apple"
        case .summerToWinter: return "Summer to Winter"
        case .winterToSummer: return "Winter to Summer"
        case .horseToZebra: return "Horse to Zebra"
        case .zebraToHorse: return "Zebra to Horse"
        case .monetToPhoto: return "Monet to Photo"
        case .photoToMonet: return "Monet Style"
        case .photoToCezanne: return "Cézanne Style"
        case .photoToUkiyoe: return "Ukiyo-e Style"
        case .photoToVanGogh: return "Van Gogh Style"
        case .cycleSatelliteToMap: return "Satellite to Map · CycleGAN"
        case .cycleMapToSatellite: return "Map to Satellite · CycleGAN"
        case .cityPhotoToLabels: return "City Photo to Labels"
        case .cityLabelsToPhoto: return "City Labels to Photo"
        case .facadePhotoToLabels: return "Facade Photo to Labels"
        case .facadeLabelsToPhoto: return "Facade Labels to Photo · CycleGAN"
        case .iphoneToDSLR: return "iPhone to DSLR"
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
        case .appleToOrange, .orangeToApple: return "leaf.fill"
        case .summerToWinter, .winterToSummer: return "snowflake"
        case .horseToZebra, .zebraToHorse: return "pawprint.fill"
        case .monetToPhoto, .photoToMonet, .photoToCezanne, .photoToUkiyoe, .photoToVanGogh: return "paintpalette.fill"
        case .cycleSatelliteToMap, .cycleMapToSatellite: return "map.fill"
        case .cityPhotoToLabels, .cityLabelsToPhoto: return "building.2.crop.circle.fill"
        case .facadePhotoToLabels, .facadeLabelsToPhoto: return "building.columns.fill"
        case .iphoneToDSLR: return "camera.fill"
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
        case .appleToOrange, .orangeToApple: return .orange
        case .summerToWinter, .winterToSummer: return .cyan
        case .horseToZebra, .zebraToHorse: return .mint
        case .monetToPhoto, .photoToMonet, .photoToCezanne, .photoToUkiyoe, .photoToVanGogh: return .purple
        case .cycleSatelliteToMap, .cycleMapToSatellite: return .green
        case .cityPhotoToLabels, .cityLabelsToPhoto: return .blue
        case .facadePhotoToLabels, .facadeLabelsToPhoto: return .brown
        case .iphoneToDSLR: return .pink
        }
    }
    var isCycleGAN: Bool { Self.cycleGANModels.contains(self) }
    var backendArchitecture: String { isCycleGAN ? "cyclegan" : (self == .cats ? "cats" : "pix2pix") }
    var engineLabel: String {
        if self == .cats { return "Legacy TensorFlow · CPU" }
        return isCycleGAN ? "PyTorch CycleGAN · Metal (MPS)" : "PyTorch pix2pix · Metal (MPS)"
    }
    var modelSize: String { self == .cats ? "193 MB" : (isCycleGAN ? "44 MB" : "208 MB") }
    var checkpointName: String {
        switch self {
        case .handbags: return "edges2handbags"
        case .shoes: return "edges2shoes"
        case .facades: return "facades_label2photo"
        case .satelliteToMap: return "sat2map"
        case .mapToSatellite: return "map2sat"
        case .dayToNight: return "day2night"
        case .cats: return "edges2cats"
        case .appleToOrange: return "apple2orange"
        case .orangeToApple: return "orange2apple"
        case .summerToWinter: return "summer2winter_yosemite"
        case .winterToSummer: return "winter2summer_yosemite"
        case .horseToZebra: return "horse2zebra"
        case .zebraToHorse: return "zebra2horse"
        case .monetToPhoto: return "monet2photo"
        case .photoToMonet: return "style_monet"
        case .photoToCezanne: return "style_cezanne"
        case .photoToUkiyoe: return "style_ukiyoe"
        case .photoToVanGogh: return "style_vangogh"
        case .cycleSatelliteToMap: return "sat2map"
        case .cycleMapToSatellite: return "map2sat"
        case .cityPhotoToLabels: return "cityscapes_photo2label"
        case .cityLabelsToPhoto: return "cityscapes_label2photo"
        case .facadePhotoToLabels: return "facades_photo2label"
        case .facadeLabelsToPhoto: return "facades_label2photo"
        case .iphoneToDSLR: return "iphone2dslr_flower"
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
        case .appleToOrange: return "1fryVqd9W7R5-5vVIU1DE1JgxS768vxoS"
        case .orangeToApple: return "1Vb3zBvo8fOBtbJFo3s6KiXQHMx_zsUu6"
        case .summerToWinter: return "1RKmxyxrV1k5Iizb4hmJxVG8sj_cgMZJO"
        case .winterToSummer: return "17axPnjiNYVYHN0HRQ6rWm4pPD11F9BUP"
        case .horseToZebra: return "1kIFYALzu8wPWBT2HOpFUYpcSoZ0bFe5m"
        case .zebraToHorse: return "1ujwe8C7liKpNFO_-2jBkarjHWpRjxgMp"
        case .monetToPhoto: return "1fdSVOorip9fwr8JtL40kumnk36GMYwHW"
        case .photoToMonet: return "12-KEHdc6E3bFplqSMwBHp9p2L2Zr6pHA"
        case .photoToCezanne: return "1d2xTmOlDq-hdoYUAT8two92fpRQmgngc"
        case .photoToUkiyoe: return "1U588oq6khqsDeWk1jqrbiNE3Nk8hIhoC"
        case .photoToVanGogh: return "1HGRYCbVH-IDzHdwnRcKUn-2VmQUzszM4"
        case .cycleSatelliteToMap: return "1CPMdXElQn8gTtJ3_DdRo6BCCcaACpmAk"
        case .cycleMapToSatellite: return "1b_yeMc0nVCxbldpVDAYm9hIZLbEjSVof"
        case .cityPhotoToLabels: return "1wnwUXHmTTjng2aXNb-SzdBqSJAh46HVo"
        case .cityLabelsToPhoto: return "18cABBd9uAABIyK-hDKKXWR3BOOlPWBP9"
        case .facadePhotoToLabels: return "1cF1hdfRWhlW-6ENnrJUlR7Na-V0_a3g7"
        case .facadeLabelsToPhoto: return "14s_xkddUM9cO4VXYhf-piit0LyYPrA9o"
        case .iphoneToDSLR: return "1n1nYXW6ABbW0pXD3fYWYsFKcXttLDORs"
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
    var requiresManualDownload: Bool { self == .cityscapes }
    var buttonLabel: String { requiresManualDownload ? "Website" : "Download" }
}

struct SketchStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
}

enum ExportSize: Int, CaseIterable, Identifiable {
    case px64 = 64, px128 = 128, px256 = 256, px512 = 512, px1024 = 1024, px2048 = 2048
    var id: Int { rawValue }
    var label: String { "\(rawValue) px" }
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}
