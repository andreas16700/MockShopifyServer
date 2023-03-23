import Vapor

// configures your application
public func configure(_ app: Application) throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
	app.http.server.configuration.port = 8082
    // register routes
	app.routes.defaultMaxBodySize = "999gb"
    try routes(app)
}
