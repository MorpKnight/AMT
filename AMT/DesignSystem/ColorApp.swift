//
//  ColorApp.swift
//  AMT
//
//  Created by Mochammad Athar Humam Ghazanfar on 24/08/26.
//

import SwiftUI

// MARK: - Color Token Definition

/// Raw color tokens loaded from Asset Catalog.
/// Structured exactly as Assets.xcassets folder hierarchy.
public enum AppColor {
    public enum token {

        // MARK: - Primary
        public static let primary0         = Color("Primary0")
        public static let primary100       = Color("Primary100")
        public static let primary200       = Color("Primary200")
        public static let primary300       = Color("Primary300")
        public static let primary500       = Color("Primary500")
        public static let primary600       = Color("Primary600")
        public static let primary700       = Color("Primary700")
        public static let primary800       = Color("Primary800")
        public static let primary900       = Color("Primary900")
        public static let primaryMain      = Color("PrimaryMain")
        public static let primarySurface   = Color("PrimarySurface")

        // MARK: - Neutral
        public static let neutral0           = Color("Neutral0")
        public static let neutral100         = Color("Neutral100")
        public static let neutral200         = Color("Neutral200")
        public static let neutral400         = Color("Neutral400")
        public static let neutral600         = Color("Neutral600")
        public static let neutral700         = Color("Neutral700")
        public static let neutral800         = Color("Neutral800")
        public static let neutralPrimary     = Color("NeutralPrimary")
        public static let neutralSecondary   = Color("NeutralSecondary")
        public static let neutralTernary     = Color("NeutralTernary")

        // MARK: - Status / Success
        public static let statusSuccessMain     = Color("StatusSuccessMain")
        public static let statusSuccessDark     = Color("StatusSuccessDark")
        public static let statusSuccessSurface  = Color("StatusSuccessSurface")

        // MARK: - Status / Error
        public static let statusErrorMain       = Color("StatusErrorMain")
        public static let statusErrorDark       = Color("StatusErrorDark")
        public static let statusErrorSurface    = Color("StatusErrorSurface")

        // MARK: - Status / Info
        public static let statusInfoMain        = Color("StatusInfoMain")
        public static let statusInfoDark        = Color("StatusInfoDark")
        public static let statusInfoSurface     = Color("StatusInfoSurface")

        // MARK: - Surface
        public static let surfaceWindowBackground   = Color("SurfaceWindowBackground")
        public static let surfaceSidebarBackground  = Color("SurfaceSidebarBackground")
        public static let surfaceCardBackground     = Color("SurfaceCardBackground")
        public static let surfaceSeparator          = Color("SurfaceSeparator")
    }
}

// MARK: - Semantic Colors

/// High-level semantic colors that map to design intent.
/// Use these in views instead of raw tokens.
public extension Color {

    // MARK: - Brand
    static let brandPrimary      = AppColor.token.primaryMain
    static let brandPrimaryLight = AppColor.token.primary100
    static let brandPrimaryDark  = AppColor.token.primary800
    static let brandSurface      = AppColor.token.primarySurface

    // MARK: - Text
    static let textPrimary       = AppColor.token.neutralPrimary
    static let textSecondary     = AppColor.token.neutralSecondary
    static let textTertiary      = AppColor.token.neutralTernary
    static let textOnPrimary     = AppColor.token.neutral0

    // MARK: - Background
    static let bgWindow          = AppColor.token.surfaceWindowBackground
    static let bgSidebar         = AppColor.token.surfaceSidebarBackground
    static let bgCard            = AppColor.token.surfaceCardBackground
    static let bgPrimary         = AppColor.token.primaryMain

    // MARK: - Border / Divider
    static let borderDefault     = AppColor.token.surfaceSeparator
    static let borderSubtle      = AppColor.token.neutral200

    // MARK: - Interactive
    static let interactiveHover    = AppColor.token.primary500
    static let interactivePressed  = AppColor.token.primary700
    static let interactiveDisabled = AppColor.token.neutral200
}
