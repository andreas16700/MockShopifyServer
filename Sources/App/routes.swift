import Vapor
import ShopifyKit

extension HTTPStatus: Error{}
extension SHVariant: Content{}
extension SHProduct: Content{}
extension InventoryLevel: Content{}
func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }

    app.get("init") { req async -> String in
		
		
        return "Init'd"
    }
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
//	public func createNewVariant(variant: SHVariantUpdate, for productID: Int) async -> SHVariant?
	app.on(.POST, ":prodID", body: .collect){req async throws -> SHVariant in
		let prodIDStr = req.parameters.get("prodID")!
		guard let prodID = Int(prodIDStr) else{throw HTTPStatus.badRequest}
		guard let varBody = try decodeToType(req.body.data, to: SHVariantUpdate.self) else{throw HTTPStatus.badRequest}
		guard let newVar = await store.createNewVariant(variant: varBody, for: prodID) else{throw HTTPStatus.badRequest}
		return newVar
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
	app.on(.POST, "batchProducts", body: .collect){req async throws -> [SHProduct] in
		guard let updateBody = try decodeToType(req.body.data, to: [SHProduct].self) else {throw HTTPStatus.badRequest}
		
		return await updateBody.asyncMap({ await store.createNewProduct(new: $0)!})
	}
//	public func createNewProduct(new given: SHProduct) async -> SHProduct?
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
//
//	public func getProduct(withID id: Int) async -> SHProduct?
	app.on(.GET, ":prodID"){req async throws -> SHProduct in
		let prodIDStr = req.parameters.get("prodID")!
		guard let prodID = Int(prodIDStr) else{throw HTTPStatus.badRequest}
		guard let prod = await store.getProduct(withID: prodID) else{throw HTTPStatus.badRequest}
		return prod
	}
//
//	public func getIDOfProduct(withHandle handle: String) async -> Int?
	app.on(.GET, "idbyhandle",":prodHandle"){req async throws -> Int in
		let prodHandle = req.parameters.get("prodHandle")!
		guard let id = await store.getIDOfProduct(withHandle: prodHandle) else{throw HTTPStatus.badRequest}
		return id
	}
//	public func updateInventory(current currentGiven: InventoryLevel, update: SHInventorySet) async -> InventoryLevel?
	app.on(.PUT, "inventories", body: .collect){req async throws -> InventoryLevel in
		guard let updateBody = try decodeToType(req.body.data, to: SHInventorySet.self) else {throw HTTPStatus.badRequest}
		let current: InventoryLevel = .init(inventoryItemID: updateBody.inventoryItemID, locationID: updateBody.locationID, updatedAt: "", adminGraphqlAPIID: "")
		guard let updated = await store.updateInventory(current: current, update: updateBody) else {throw HTTPStatus.badRequest}
		return updated
	}
	
//	public func getInventory(of invItemID: Int) async -> InventoryLevel?
	app.on(.GET, "inventories/:invItemID"){req async throws -> InventoryLevel in
		let invItemIDStr = req.parameters.get("invItemID")!
		guard let invItemID = Int(invItemIDStr) else{throw HTTPStatus.badRequest}
		guard let inv = await store.getInventory(of: invItemID) else{throw HTTPStatus.badRequest}
		return inv
	}
	//MARK: Paginated Routes
	app.get("productsP",":pageNumber"){req async throws -> [SHProduct] in
		let pageNumStr = req.parameters.get("pageNumber")!
		guard let pageNum = Int(pageNumStr) else{throw HTTPStatus.badRequest}
		guard let f = await store.getProductsPage(pageNum: pageNum) else{throw HTTPStatus.badRequest}
		return f
		
	}
	app.get("inventoriesP",":pageNumber"){req async throws -> [InventoryLevel] in
		let pageNumStr = req.parameters.get("pageNumber")!
		guard let pageNum = Int(pageNumStr) else{throw HTTPStatus.badRequest}
		guard let f = await store.getInventoriesPage(pageNum: pageNum) else{throw HTTPStatus.badRequest}
		return f
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
var store = MockShopifyStore(products: [], locations: [], inventoriesByLocationID: .init())
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
