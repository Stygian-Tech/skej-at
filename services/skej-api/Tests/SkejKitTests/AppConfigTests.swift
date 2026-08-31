import SkejGateway
import Testing

@Suite
struct AppConfigTests {
    @Test func dotenvProvidesOAuthOriginAndEnvironmentDefaults() {
        let config = AppConfig.load(
            environment: [:],
            dotenv: [
                "APP_ENV": "dev",
                "PORT": "9000",
                "SKEJ_PUBLIC_ORIGIN": "https://api.testing.skej.at/",
                "SKEJ_WEB_ORIGIN": "https://testing.skej.at/",
                "SKEJ_SQLITE_PATH": "data/dev.sqlite",
                "SKEJ_WORKER_ENABLED": "false",
                "SKEJ_WORKER_INTERVAL_SECONDS": "45",
                "SKEJ_LIVE_ATPROTO_ENABLED": "false",
            ]
        )

        #expect(config.environment == .dev)
        #expect(config.port == 9000)
        #expect(config.publicOrigin == "https://api.testing.skej.at")
        #expect(config.webOrigin == "https://testing.skej.at")
        #expect(config.sqlitePath == "/var/lib/skej-api/data/skej.sqlite")
        #expect(config.workerEnabled == false)
        #expect(config.workerIntervalSeconds == 45)
        #expect(config.liveATProtoEnabled == false)
    }

    @Test func processEnvironmentOverridesDotenvValues() {
        let config = AppConfig.load(
            environment: [
                "APP_ENV": "prod",
                "SKEJ_PUBLIC_ORIGIN": "https://skej.at",
            ],
            dotenv: [
                "APP_ENV": "dev",
                "SKEJ_PUBLIC_ORIGIN": "https://testing.skej.at",
            ]
        )

        #expect(config.environment == .prod)
        #expect(config.publicOrigin == "https://skej.at")
        #expect(config.liveATProtoEnabled == true)
    }

    @Test func legacyPublicOriginRemainsFallback() {
        let config = AppConfig.load(
            environment: [:],
            dotenv: [
                "PUBLIC_ORIGIN": "https://legacy.example",
            ]
        )

        #expect(config.publicOrigin == "https://legacy.example")
    }

    @Test func hostedEnvironmentsUseMountedSQLitePathWhenConfiguredPathIsRelative() {
        let config = AppConfig.load(
            environment: [:],
            dotenv: [
                "APP_ENV": "dev",
                "SKEJ_SQLITE_PATH": "data/skej.sqlite",
            ]
        )

        #expect(config.sqlitePath == "/var/lib/skej-api/data/skej.sqlite")
    }

    @Test(arguments: ["local", "test", "dev"])
    func proFeaturesDefaultOnOutsideProd(appEnv: String) {
        let config = AppConfig.load(environment: ["APP_ENV": appEnv])
        #expect(config.proFeaturesEnabled == true)
    }

    @Test func proFeaturesDefaultOffInProd() {
        let config = AppConfig.load(environment: ["APP_ENV": "prod"])
        #expect(config.proFeaturesEnabled == false)
    }

    @Test(arguments: ["false", "0", "no"])
    func proFeaturesCanBeDisabledExplicitly(value: String) {
        let config = AppConfig.load(environment: ["APP_ENV": "local", "SKEJ_PRO_ENABLED": value])
        #expect(config.proFeaturesEnabled == false)
    }

    @Test(arguments: ["true", "1"])
    func proFeaturesCanBeEnabledInProd(value: String) {
        let config = AppConfig.load(environment: ["APP_ENV": "prod", "SKEJ_PRO_ENABLED": value])
        #expect(config.proFeaturesEnabled == true)
    }

    @Test func engagementCollectorUsesDocumentedEnvironmentNames() {
        let config = AppConfig.load(environment: [
            "SKEJ_ENGAGEMENT_ENABLED": "false",
            "SKEJ_ENGAGEMENT_INTERVAL_SECONDS": "1200",
            "SKEJ_BSKY_APPVIEW_ORIGIN": "https://appview.example/",
        ])

        #expect(config.engagementCollectorEnabled == false)
        #expect(config.engagementCollectorIntervalSeconds == 1200)
        #expect(config.engagementAppViewOrigin == "https://appview.example")
    }
}
