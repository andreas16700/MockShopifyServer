import Vapor
import MockShopifyClient
import ShopifyClient


func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }

    app.get("init") { req async -> String in
		
		
        return "Init'd"
    }
	
}
//var store = MockShopifyStore
