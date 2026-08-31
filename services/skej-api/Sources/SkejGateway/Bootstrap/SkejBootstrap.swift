import Foundation
import Hummingbird
import Logging
import SkejKit

public enum SkejBootstrap {
    public static func run(config: AppConfig, services: SkejServices, logger: Logger) async throws {
        let router = buildRouter(services: services)
        let app = Application(
            router: router,
            configuration: .init(address: .hostname("0.0.0.0", port: config.port))
        )
        let worker = ScheduleWorker(store: services.store, pdsClient: services.pdsClient, logger: logger)
        let engagementCollector = EngagementCollectorRuntime(services: services, logger: logger)
        logger.info("skej-api listening on port \(config.port)")

        if config.workerEnabled || config.engagementCollectorEnabled {
            try await withThrowingTaskGroup(of: Void.self) { group in
                if config.workerEnabled {
                    group.addTask {
                        while !Task.isCancelled {
                            await worker.runTick()
                            try await Task.sleep(for: .seconds(config.workerIntervalSeconds))
                        }
                    }
                }
                if config.engagementCollectorEnabled {
                    group.addTask {
                        while !Task.isCancelled {
                            await engagementCollector.runTick()
                            try await Task.sleep(for: .seconds(config.engagementCollectorIntervalSeconds))
                        }
                    }
                }
                group.addTask { try await app.runService() }
                try await group.next()
                group.cancelAll()
            }
        } else {
            try await app.runService()
        }
    }
}
