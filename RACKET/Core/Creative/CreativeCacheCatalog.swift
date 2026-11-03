import Foundation

/// Presentation metadata for the bundled candidate. Verification/enabling lives
/// in the rule document, and all paths still pass the independent compiled policy.
public enum CreativeCacheCatalog {
    public static let ruleMappings: [CreativeCacheRuleMapping] = [
        CreativeCacheRuleMapping(
            ruleID: "adobe.camera-raw-cache-2",
            producerIDs: ["com.adobe.LightroomClassicCC7", "com.adobe.Photoshop", "com.adobe.bridge",
                          "com.adobe.AfterEffects.application", "com.adobe.AfterEffectsRenderEngine"],
            producerName: "Adobe Camera Raw", scope: .applicationWide
        )
    ]
}
