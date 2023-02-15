import Vapor
import MockPowersoftClient

func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }

    app.get("init") { req async -> String in
		
		
        return "Init'd"
    }
	
}
//var store = MockPowersoftStore(models: <#T##[String : [PSItem]]#>, modelsMetadata: <#T##[String : PSListModel]#>, stockByItemCode: <#T##[String : PSListStockStoresItem]#>)
