import Vapor
import ShopifyKit

extension HTTPStatus: Error{}
extension SHVariant: Content{}
extension SHProduct: Content{}
extension InventoryLevel: Content{}
extension SHLocation: Content{}


struct Wrapper<T: Codable>: Codable, Content{
	let content: T
}
func handleStream(_ req: Request) -> EventLoopFuture<Response> {
	let promise = req.eventLoop.makePromise(of: Response.self)
	
	var buffer = ByteBuffer()
	req.body.drain { chunk in
		switch chunk {
		case .buffer(var data):
			buffer.writeBuffer(&data)
		case .end:
			let response = Response(status: .ok)
//			let g: Data = .ini
			promise.succeed(response)
		case .error(let error):
			promise.fail(error)
		}
		return req.eventLoop.future()
	}
	
	return promise.futureResult
}
func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }
//	app.on(.PUT, "up", body: .stream){req async -> String in
//		req.body.drain(<#T##handler: (BodyStreamResult) -> EventLoopFuture<Void>##(BodyStreamResult) -> EventLoopFuture<Void>#>)
//		return "ok"
//	}
	app.get("randomP"){req async -> String in
		guard let p = await store.allProducts.randomElement() else {return "empty store!"}
		return showThing(p)
	}
    app.get("init") { req async -> String in
		
		
        return "Init'd"
    }
	app.get("reset"){req async -> HTTPStatus in
		await store.reset()
		return .ok
	}
	app.get("generate"){req async -> HTTPStatus in
		let prodCount = 1_000
		let prods = Array(0..<prodCount).map{prodID in
			let varCount = Int.random(in: 1...20)
			let variants = Array(0..<varCount).map{varID in
				SHVariant(id: Int.random(in: 111111...999999), productID: prodID, sku: String(UUID().uuidString.prefix(3)))
			}
			return SHProduct(id: prodID, title: "some\(prodID)", handle: "prod\(prodID)", variants: variants)
		}
		let _ = await prods.asyncMap{await store.createNewProduct(new: $0)}
		return .ok
	}
	//MARK: Variant
//	public func deleteVariant(ofProductID productID: Int, variantID: Int) async -> Bool
	app.on(.DELETE, ":prodID",":varID"){req async throws -> HTTPStatus in
		let prodIDStr = req.parameters.get("prodID")!
		let varIDStr = req.parameters.get("varID")!
		guard let prodID = Int(prodIDStr), let varID = Int(varIDStr) else{return .badRequest}
		let deleted = await store.deleteVariant(ofProductID: prodID, variantID: varID)
		guard deleted else {return .badRequest}
		return .ok
	}
	//	public func updateVariant(with update: SHVariantUpdate) async -> SHVariant?
	app.on(.PUT, "variants", body: .collect){req async throws -> SHVariant in
		guard let updateBody = try decodeToType(req.body.data, to: SHVariantUpdate.self) else {throw HTTPStatus.badRequest}
		guard let variant = await store.updateVariant(with: updateBody) else {throw HTTPStatus.badRequest}
		return variant
	}
	//	public func updateVariants(with updates: [SHVariantUpdate]) async -> [SHVariant]?
	app.on(.PUT, "variants","multiple", body: .collect){req async throws -> [SHVariant] in
		guard let updateBody = try decodeToType(req.body.data, to: [SHVariantUpdate].self) else {throw HTTPStatus.badRequest}
		var updated: [SHVariant?] = .init(repeating: nil, count: updateBody.count)
		for i in 0..<updateBody.count{
			updated[i] = await store.updateVariant(with: updateBody[i])
		}
		return updated.compactMap{$0}
	}
	//	public func createNewVariant(variant: SHVariantUpdate, for productID: Int) async -> SHVariant?
	app.on(.POST, ":prodID", body: .collect){req async throws -> SHVariant in
		let prodIDStr = req.parameters.get("prodID")!
		guard let prodID = Int(prodIDStr) else{throw HTTPStatus.badRequest}
		guard let varBody = try decodeToType(req.body.data, to: SHVariantUpdate.self) else{throw HTTPStatus.badRequest}
		guard let newVar = await store.createNewVariant(variant: varBody, for: prodID) else{throw HTTPStatus.internalServerError}
		return newVar
	}
//	public func createNewViariants(variants: [SHVariantUpdate], for productID: Int) async -> [SHVariant]?
	app.on(.POST, ":prodID","multiple", body: .collect){req async throws -> [SHVariant] in
		let prodIDStr = req.parameters.get("prodID")!
		guard let prodID = Int(prodIDStr) else{throw HTTPStatus.badRequest}
		guard let varsBody = try decodeToType(req.body.data, to: [SHVariantUpdate].self) else{throw HTTPStatus.badRequest}
		let receivedVars =  await varsBody.asyncMap{
			return await store.createNewVariant(variant: $0, for: prodID)
		}
		let vars: [SHVariant] = receivedVars.compactMap{$0}
		return vars
	}
	//MARK: Product
		app.on(.GET,"products","page",":pageNum"){req async throws -> [SHProduct] in
			guard let pageNum = req.parameters.get("pageNum", as: Int.self) else {throw HTTPStatus.badRequest}
			guard let page = await store.getProductsPage(pageNum: pageNum) else {throw HTTPStatus.internalServerError}
			return page
		}
		app.on(.GET,"products","count"){req async throws -> Wrapper<Int> in
		let count = await store.allProducts.count
		return Wrapper(content: count)
		}
	//	public func deleteProduct(id: Int) async -> Bool
		app.on(.DELETE, ":prodID"){req async throws -> HTTPStatus in
			let prodIDStr = req.parameters.get("prodID")!
			guard let prodID = Int(prodIDStr) else{return HTTPStatus.badRequest}
			guard await store.deleteProduct(id: prodID) else {return HTTPStatus.badRequest}
			return .ok
		}
	//	public func updateProduct(with update: SHProductUpdate) async -> SHProduct?
		app.on(.PUT, "products", body: .collect){req async throws -> SHProduct in
			guard let updateBody = try decodeToType(req.body.data, to: SHProductUpdate.self) else {throw HTTPStatus.badRequest}
			guard let product = await store.updateProduct(with: updateBody) else {throw HTTPStatus.badRequest}
			return product
		}
	//	public func createNewProducts(new given: [SHProduct]) async -> [SHProduct]?
		app.on(.POST, "batchProductsAndStocks", body: .collect){req async throws -> HTTPStatus in
			guard let updateBody = try decodeToType(req.body.data, to: [ProductAndItsStocks].self) else {throw HTTPStatus.badRequest}
			let _ = await updateBody.asyncMap({
				await store.createNewProduct(new: $0.product, inventoriesBySKU: $0.stocksBySKU)!
			})
			return .ok
		}
	//	public func createNewProduct(new: SHProduct) async -> SHProduct?
		app.on(.POST, "products", body: .collect){req async throws -> SHProduct in
			guard let prodBody = try decodeToType(req.body.data, to: SHProduct.self) else{throw HTTPStatus.badRequest}
			guard let newProd = await store.createNewProduct(new: prodBody) else{throw HTTPStatus.badRequest}
			return newProd
		}
	//	public func getProduct(withHandle handle: String) async -> SHProduct?
		app.on(.GET, "handles",":prodHandle"){req async throws -> SHProduct in
			let prodHandle = req.parameters.get("prodHandle")!
			guard let prod = await store.getProduct(withHandle: prodHandle) else{throw HTTPStatus.badRequest}
			return prod
		}
	//	public func getProduct(withID id: Int) async -> SHProduct?
		app.on(.GET, ":prodID"){req async throws -> SHProduct in
			let prodIDStr = req.parameters.get("prodID")!
			guard let prodID = Int(prodIDStr) else{throw HTTPStatus.badRequest}
			guard let prod = await store.getProduct(withID: prodID) else{throw HTTPStatus.badRequest}
			return prod
		}
	//	public func getIDOfProduct(withHandle handle: String) async -> Int?
		app.on(.GET, "idbyhandle",":prodHandle"){req async throws -> Wrapper<Int> in
			let prodHandle = req.parameters.get("prodHandle")!
			guard let id = await store.getIDOfProduct(withHandle: prodHandle) else{throw HTTPStatus.badRequest}
			return .init(content: id)
		}
	//	public func getAllProducts() async -> [SHProduct]?
	//paginated(?)
	
	//MARK: Inventory
	app.on(.GET,"inventories","page",":pageNum"){req async throws -> [InventoryLevel] in
		guard let pageNum = req.parameters.get("pageNum", as: Int.self) else {throw HTTPStatus.badRequest}
		guard let page = await store.getInventoriesPage(pageNum: pageNum) else {throw HTTPStatus.internalServerError}
		return page
	}
	app.on(.GET,"inventories",":locationID","page",":pageNum"){req async throws -> [InventoryLevel] in
		guard let pageNum = req.parameters.get("pageNum", as: Int.self),
			  let locID = req.parameters.get("locationID", as: Int.self) else {throw HTTPStatus.badRequest}
		guard let page = await store.getInventoriesPage(pageNum: pageNum, locationID: locID) else {throw HTTPStatus.internalServerError}
		return page
	}
	app.on(.GET,"inventories","count"){req async throws -> Wrapper<Int> in
		let count = await store.allInventories.count
		return Wrapper(content: count)
	}
	app.on(.GET,"inventoriesCount",":locationID"){req async throws -> Wrapper<Int> in
		guard let locID = req.parameters.get("locationID", as: Int.self) else {throw HTTPStatus.badRequest}
		guard let count = await store.inventoriesByLocationIDByInvID[locID]?.values.count else {throw HTTPStatus.internalServerError}
		
		return Wrapper(content: count)
	}
	//	public func updateInventory(current: InventoryLevel, update: SHInventorySet) async -> InventoryLevel?
	app.on(.PUT, "inventories", body: .collect){req async throws -> InventoryLevel in
		guard let updateBody = try decodeToType(req.body.data, to: SHInventorySet.self) else {throw HTTPStatus.badRequest}
		let current: InventoryLevel = .init(inventoryItemID: updateBody.inventoryItemID, locationID: updateBody.locationID, updatedAt: "", adminGraphqlAPIID: "")
		guard let updated = await store.updateInventory(current: current, update: updateBody) else {throw HTTPStatus.badRequest}
		return updated
	}
//	func updateInventories(updates: [SHInventorySet])async->[InventoryLevel]?
	app.on(.PUT, "inventories","multiple", body: .collect){req async throws -> [InventoryLevel] in
		guard let updateBody = try decodeToType(req.body.data, to: [SHInventorySet].self) else {throw HTTPStatus.badRequest}
		let currents: [InventoryLevel] = updateBody.map{
			.init(inventoryItemID: $0.inventoryItemID, locationID: $0.locationID, updatedAt: "", adminGraphqlAPIID: "")
		}
			
			
		guard let updated = await store.updateInventories(currents: currents, updates: updateBody) else {throw HTTPStatus.badRequest}
		return updated
	}
	
	//	public func getInventory(of invItemID: Int) async -> InventoryLevel?
	app.on(.GET,"inventory",":invItemID"){req async throws -> InventoryLevel in
		guard let invItemID = req.parameters.get("invItemID", as: Int.self) else{throw HTTPStatus.badRequest}
		guard let inv = await store.getInventory(of: invItemID) else{throw HTTPStatus.internalServerError}
		return inv
	}
	//public func getInventories(of invItemIDs: [Int]) async -> [InventoryLevel]?
	app.on(.POST,"inventories","multiple", body: .collect){req async throws -> [InventoryLevel] in
		guard let ids = try decodeToType(req.body.data, to: [Int].self) else {throw HTTPStatus.badRequest}
		guard let invs = await store.getInventories(of: ids) else {throw HTTPStatus.internalServerError}
				
		return invs
	}
	//	public func getAllInventories() async -> [InventoryLevel]?
	//paginated
	//	public func getAllInventories(of locationID: Int) async -> [InventoryLevel]?
	//paginated
	//	public func getAllLocations() async -> [SHLocation]?
	app.on(.GET, "locations"){req async throws -> [SHLocation] in
		return await store.locations
	}
	
	
}
func decodeToType<T: Decodable>(_ b: ByteBuffer?, to type: T.Type)throws ->T?{
	guard let buf = b else {try reportError(ServerErrors.emptyBody); return nil}
	return try decoder.decode(T.self, from: buf)
}
func reportError(_ e: Error? = nil, _ msg: String? = nil)throws{
	if let msg{
		print(msg)
	}
	if let e{
		print("\(e)")
	}
	throw e ?? ServerErrors.other(msg ?? "unknown error occured")
}
enum ServerErrors:Error{
	case emptyBody
	case nonUTF8Body
	case nonDecodableBody
	case other(String)
}
var store = MockShopifyStore(products: .init(), locations: .init(), inventoriesByLocationIDByInvID: .init())
let encoder = JSONEncoder()
let decoder = JSONDecoder()
extension MockShopifyStore{
	var pageSize: Int {100}
	
}
extension Collection{
	func asyncMap<T>(_ transform: (Element)async throws->T)async rethrows->[T]{
		var r: [T] = .init()
		for item in self{
			let e = try await transform(item)
			r.append(e)
		}
		return r
	}
}
func showThing<T: Encodable>(_ t: T)->String{
	guard let s = try? encoder.encode(t), let str = String(data: s, encoding: .utf8) else {return "Error!"}
	return """
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1.0">
	<title>Show JSON Object</title>
	<link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.16/dist/tailwind.min.css" rel="stylesheet">
</head>
<body class="bg-gray-100">
	<div class="container mx-auto px-4 py-8">
		<div class="bg-white p-6 rounded-lg shadow-md">
			<pre class="text-gray-800 font-mono whitespace-pre-wrap">\(str)</pre>
		</div>
	</div>
</body>
</html>

"""
}
