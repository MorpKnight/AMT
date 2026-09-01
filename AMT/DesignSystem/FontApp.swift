//
//  FontApp.swift
//  AMT
//
//  Created by Fajari Bagas on 30/08/26.
//

import SwiftUI

/// Defines the supported weights for the Inter custom font family.
public enum AppFontWeight {
    case regular
    case medium
    case semibold
    case bold
    
    public var suffix: String {
        switch self {
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "SemiBold"
        case .bold: return "Bold"
        }
    }
    
    public var systemWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

/// Defines the semantic text styles matching the design scale.
public enum AppTextStyle {
    case displayLarge    // 64
    case displayMedium   // 48
    case displaySmall    // 32
    case titleLarge      // 24
    case titleMedium     // 20
    case body            // 17 (base)
    case subheadline     // 15
    case callout         // 13
    case caption         // 11
    
    public var size: CGFloat {
        switch self {
        case .displayLarge: return 64
        case .displayMedium: return 48
        case .displaySmall: return 32
        case .titleLarge: return 24
        case .titleMedium: return 20
        case .body: return 17
        case .subheadline: return 15
        case .callout: return 13
        case .caption: return 11
        }
    }
    
    public var defaultWeight: AppFontWeight {
        switch self {
        case .displayLarge, .displayMedium, .displaySmall:
            return .bold
        case .titleLarge, .titleMedium:
            return .semibold
        case .body, .subheadline, .callout, .caption:
            return .regular
        }
    }
    
    public var relativeTextStyle: Font.TextStyle {
        switch self {
        case .displayLarge, .displayMedium: return .largeTitle
        case .displaySmall: return .title
        case .titleLarge: return .title2
        case .titleMedium: return .title3
        case .body: return .body
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .caption: return .caption
        }
    }
}

public extension Font {
    /// Generates a custom Inter font style with the specified size and weight, falling back gracefully to system fonts if not registered.
    /// It dynamically scales relative to the specified system text style (supporting Dynamic Type).
    static func appFont(size: CGFloat, weight: AppFontWeight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        let fontName = "Inter-\(weight.suffix)"
        return Font.custom(fontName, size: size, relativeTo: textStyle)
    }
    
    /// Static accessors for the semantic design system styles.
    enum App {
        public static func displayLarge(weight: AppFontWeight = .bold) -> Font {
            .appFont(size: 64, weight: weight, relativeTo: .largeTitle)
        }
        
        public static func displayMedium(weight: AppFontWeight = .bold) -> Font {
            .appFont(size: 48, weight: weight, relativeTo: .largeTitle)
        }
        
        public static func displaySmall(weight: AppFontWeight = .bold) -> Font {
            .appFont(size: 32, weight: weight, relativeTo: .title)
        }
        
        public static func titleLarge(weight: AppFontWeight = .semibold) -> Font {
            .appFont(size: 24, weight: weight, relativeTo: .title2)
        }
        
        public static func titleMedium(weight: AppFontWeight = .semibold) -> Font {
            .appFont(size: 20, weight: weight, relativeTo: .title3)
        }
        
        public static func body(weight: AppFontWeight = .regular) -> Font {
            .appFont(size: 17, weight: weight, relativeTo: .body)
        }
        
        public static func subheadline(weight: AppFontWeight = .regular) -> Font {
            .appFont(size: 15, weight: weight, relativeTo: .subheadline)
        }
        
        public static func callout(weight: AppFontWeight = .regular) -> Font {
            .appFont(size: 13, weight: weight, relativeTo: .callout)
        }
        
        public static func caption(weight: AppFontWeight = .regular) -> Font {
            .appFont(size: 11, weight: weight, relativeTo: .caption)
        }
    }
}

/// View modifier to cleanly apply the brand typography styling.
public struct AppFontModifier: ViewModifier {
    let size: CGFloat
    let weight: AppFontWeight
    let relativeTo: Font.TextStyle
    
    public func body(content: Content) -> some View {
        content.font(.appFont(size: size, weight: weight, relativeTo: relativeTo))
    }
}

public extension View {
    /// Applies a custom size and weight using the brand Inter font configuration.
    func appFont(size: CGFloat, weight: AppFontWeight = .regular, relativeTo: Font.TextStyle = .body) -> some View {
        modifier(AppFontModifier(size: size, weight: weight, relativeTo: relativeTo))
    }
    
    /// Applies a semantic text style with its default weight, or overrides it.
    func appFont(_ style: AppTextStyle, weight: AppFontWeight? = nil) -> some View {
        modifier(AppFontModifier(size: style.size, weight: weight ?? style.defaultWeight, relativeTo: style.relativeTextStyle))
    }
}
