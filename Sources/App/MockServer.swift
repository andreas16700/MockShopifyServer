//
//  File.swift
//  
//
//  Created by Andreas Loizides on 19/02/2023.
//

import Foundation
import ShopifyKit
extension SHLocation{
	static func defaultLoc()->Self{
		return .init(id: 5, name: "default", country: "", createdAt: "", updatedAt: "", countryCode: "", countryName: "", legacy: false, active: true, adminGraphqlAPIID: "", localizedCountryName: "")
	}
}

class IDRepo{
	init(range: ClosedRange<Int>){
		print("Generating ID repo for range \(range)")
		var rng: RandomNumberGenerator = Xorshift128Plus(xSeed: 3199077918806463242, ySeed: 11403738689752549865)
		arr = Array(range).shuffled(using: &rng)
		nextIndex = 0
		highestID = range.upperBound
		print("Done generating ID repo for range \(range)")
	}
	private var arr: [Int]
	private var nextIndex: Int
	var highestID: Int
	func next()->Int?{
		guard nextIndex<arr.count else {
			return nil
		}
		defer{
			nextIndex+=1
			if nextIndex>=arr.count{
				expand()
			}
		}
		return arr[nextIndex]
	}
	func reset(){
		nextIndex = 0
	}
	func expand(expandSize: Int = 50_000){
		print("Expanding ID repo for \(expandSize) more IDs..")
		let newB = highestID+1
		let newEnd = newB+expandSize
		var rng: RandomNumberGenerator = Xorshift128Plus(xSeed: 3199077918806463242, ySeed: 11403738689752549865)
		let arrExtension = Array(newB...newEnd).shuffled(using: &rng)
		nextIndex = arr.count
		arr.append(contentsOf: arrExtension)
	}
}
//May be needed later
//actor Stack<T: Hashable>{
//	init(initialCapacity: Int){
//		arr = .init(repeating: nil, count: initialCapacity)
//		nextIndex = 0
//	}
//	private var arr: [T?]
//	//nextIndex is the index of the next (new) item to push
//	private var nextIndex: Int
//	func makeSureTheseNewItemsFit(count: Int){
//		let spares = arr.count - nextIndex
//		let extraNeeded = count-spares
//		guard extraNeeded>0 else {return}
//		expand()
//	}
//	func pop()->T?{
//		guard nextIndex - 1 >= 0 else {return nil}
//		nextIndex-=1
//		defer{arr[nextIndex]=nil}
//		return arr[nextIndex]
//	}
//	func push(t: T){
//		arr[nextIndex]=t
//		nextIndex+=1
//		guard nextIndex<arr.count else {
//			expand()
//			assert(nextIndex<arr.count)
//			return
//		}
//	}
//	private func expand(){
//		let extensionSize = arr.count/4
//		arr.reserveCapacity(arr.count+extensionSize)
//		for _ in 0..<extensionSize{
//			arr.append(nil)
//		}
//	}
//	func removeAll(keepingCapacity: Bool){
//
//	}
//}
public actor MockShopifyStore{
	static let PAGE_SIZE = 10000
	public init(products: [SHProduct], locations: [SHLocation], inventoriesByLocationIDByInvID: [Int : [Int: InventoryLevel]], defaultLocationID: Int? = nil) {
		self.productsByID = products.reduce(into: [Int: SHProduct]()){dict, prod in
			dict[prod.id!]=prod
		}
		self.locations = locations.isEmpty ? [.defaultLoc()] : locations
		self.inventoriesByLocationIDByInvID = inventoriesByLocationIDByInvID
		self.defaultLocationID = self.locations.first!.id
		if self.inventoriesByLocationIDByInvID[self.defaultLocationID] == nil{
			self.inventoriesByLocationIDByInvID[self.defaultLocationID] = .init()
		}
	}
	
	var productsByID: [Int: SHProduct]
	var locations: [SHLocation]
	var inventoriesByLocationIDByInvID: [Int: [Int: InventoryLevel]]
	let defaultLocationID: Int
	static let productIDRepo = IDRepo(range: 100000...999999)
	static let variantIDRepo = IDRepo(range: 100000...999999)
	static let invIDRepo = IDRepo(range: 100000...999999)
//	static func generateID()->Int{
//		return IDRepo.shared.next()!
//	}
	//MARK: Public
	public func reset(){
		print("Resetting productsByID..")
		productsByID.removeAll(keepingCapacity: true)
		print("Resetting ID repos..")
		Self.productIDRepo.reset()
		Self.variantIDRepo.reset()
		Self.invIDRepo.reset()
		for (k,_) in inventoriesByLocationIDByInvID{
			print("Resetting location \(k)..")
			inventoriesByLocationIDByInvID[k]!.removeAll(keepingCapacity: true)
		}
		print("Reset done!")
	}
	public func deleteVariant(ofProductID productID: Int, variantID: Int) async -> Bool {
		guard let variantIndex = indexOfVariant(productID: productID, variantID: variantID) else {return false}
		productsByID[productID]!.variants.remove(at: variantIndex)
		return true
	}
	
	public func updateVariant(with update: SHVariantUpdate) async -> SHVariant? {
		guard let variantID = update.id else{
			reportError("Variant updated does not contain an id!")
			return nil
		}
		guard let (productID, variantIndex) = productIDAndIndexOfVariant(variantID: variantID)else{return nil}
		
		let variantGetter = {self.productsByID[productID]?.variants[variantIndex]}
		let variantSetter = {self.productsByID[productID]!.variants[variantIndex]=$0}
		return await processCurrentAndReturnIfPossible(get: variantGetter, set: variantSetter){variantToModify in
			variantToModify.applyUpdate(from: update)
		}
	}
	public func createNewVariant(variant: SHVariantUpdate, for productID: Int) async -> SHVariant? {
		guard productsByID[productID] != nil else{
			print("Can't create variant for product with id \(productID) as no product exists with that id.")
			return nil
		}
		let (variant, inventory) = Self.generateNewVariant(variant: variant, for: productID, onLocationID: defaultLocationID)
		inventoriesByLocationIDByInvID[defaultLocationID]![inventory.inventoryItemID] = inventory
		return variant
	}
	
	public func deleteProduct(id: Int) async -> Bool {
		return productsByID.removeValue(forKey: id) != nil
	}
	private func addInventory(_ i: InventoryLevel){
		inventoriesByLocationIDByInvID[defaultLocationID]![i.inventoryItemID] = i
	}
	public func updateProduct(with update: SHProductUpdate) async -> SHProduct? {
		let productID = update.id
		guard productsByID[productID] != nil else{
			print("Can't update product with id \(productID) as no product exists with that id.")
			return nil
		}
		
		let getter: ()async->SHProduct = {self.productsByID[productID]!}
		let setter: (SHProduct)async->() = {self.productsByID[productID]=$0}
		return await processCurrentAndReturnIfPossible(get: getter, set: setter){existingProduct in
			func applyUpdate<T>(using: WritableKeyPath<SHProduct,T>, from: KeyPath<SHProductUpdate,T?>){
				App.applyUpdate(on: &existingProduct, using: using, from: from, from: update)
			}
			func applyUpdate<T>(using: WritableKeyPath<SHProduct,T?>, from: KeyPath<SHProductUpdate,T?>){
				App.applyUpdate(on: &existingProduct, using: using, from: from, from: update)
			}
			let original = existingProduct
			applyUpdate(using: \.title, from: \.title)
			applyUpdate(using: \.bodyHTML, from: \.body_html)
			applyUpdate(using: \.productType, from: \.product_type)
			applyUpdate(using: \.vendor, from: \.vendor)
			applyUpdate(using: \.tags, from: \.tags)
			guard let varUpds = update.variants else {return}
			if let optionUpds = update.options{
				guard productUpdateHasValidOptions(options: optionUpds, vars: varUpds) else {existingProduct=original; return}
				existingProduct.options!.applyUpdate(from: optionUpds, productID: existingProduct.id!)
			}else{
				guard productUpdateHasValidOptions(options: existingProduct.options!, vars: varUpds) else {existingProduct=original; return}
			}
			for varUpd in varUpds {
				if let varID = varUpd.id, let indexOfExisting = existingProduct.variants.firstIndex(where: {$0.id == varID}){
					existingProduct.variants[indexOfExisting].applyUpdate(from: varUpd)
				}else{
					let (createdVar, createdInv) = Self.generateNewVariant(variant: varUpd, for: existingProduct.id!, onLocationID: defaultLocationID)
					existingProduct.variants.append(createdVar)
					addInventory(createdInv)
				}
			}
		}
	}
	private static func generateNewProduct(new given: SHProduct, locationID: Int)->(SHProduct, [InventoryLevel]){
		var new = given
		let productID = Self.productIDRepo.next()!
		new.id = productID
		new.createdAt = formatter.string(from: Date())
		new.updatedAt = formatter.string(from: Date())
		var inventories = [InventoryLevel]()
		for i in 0..<new.variants.count{
			new.variants[i].id = Self.variantIDRepo.next()!
			new.variants[i].productID = productID
			let inventoryItemID = Self.invIDRepo.next()!
			new.variants[i].inventoryItemID = inventoryItemID
			let inventory = InventoryLevel(inventoryItemID: inventoryItemID, locationID: locationID, available: 0, updatedAt: formatter.string(from: Date()), adminGraphqlAPIID: "")
			inventories.append(inventory)
			new.variants[i].createdAt = formatter.string(from: Date())
			new.variants[i].updatedAt = formatter.string(from: Date())
		}
		//TODO more processing
		
		return (new,inventories)
	}
	public func createNewProduct(new given: SHProduct, inventoriesBySKU: [String: Int]? = nil) async -> SHProduct? {
		let (generated, inventories) = Self.generateNewProduct(new: given, locationID: defaultLocationID)
		productsByID[generated.id!] = generated
		if let inventoriesBySKU{
			let skuByInvID = generated.variants.reduce(into: [Int: String](minimumCapacity: generated.variants.count)){
				$0[$1.inventoryItemID!]=$1.sku
			}
			var modifiedInvs = inventories
			for i in 0..<modifiedInvs.count{
				let invID = modifiedInvs[i].inventoryItemID
				let sku = skuByInvID[invID]!
				modifiedInvs[i].available = inventoriesBySKU[sku]!
			}
			modifiedInvs.forEach{addInventory($0)}
		}else{
			inventories.forEach{addInventory($0)}
		}
		
		
		return generated
	}
	var allProducts: [SHProduct] {Array(productsByID.values)}
	public func getAllProducts() async -> [SHProduct]? {
		return allProducts
	}
	private func getPage<T>(allGetter: ()->[T], pageNum: Int)->[T]?{
		let all = allGetter()
		let maxPage = all.count / pageSize
		let finalPage = maxPage*pageSize < all.count ? maxPage+1 : maxPage
		guard pageNum >= 0 && pageNum <= finalPage else {reportError("GetAll: Requested page \(pageNum) isn't in range 0...\(finalPage)!"); return nil}
		let firstIndex = pageNum*pageSize
		let lastIndex = min(firstIndex+pageSize-1, all.count-1)
		let slice = all[firstIndex...lastIndex]
		return Array(slice)
	}
	public func getProductsPage(pageNum: Int)->[SHProduct]?{
		return allProducts.getPaginatedSlice(pageNumber: pageNum, pageSize: Self.PAGE_SIZE)
//		return getPage(allGetter: {allProducts}, pageNum: pageNum)
	}
	public func getInventoriesPage(pageNum: Int)->[InventoryLevel]?{
		return allInventories.getPaginatedSlice(pageNumber: pageNum, pageSize: Self.PAGE_SIZE)
//		return getPage(allGetter: {allInventories}, pageNum: pageNum)
	}
	public func getInventoriesPage(pageNum: Int, locationID: Int)->[InventoryLevel]?{
		guard let invs = inventoriesByLocationIDByInvID[locationID] else {return nil}
		return Array(invs.values).getPaginatedSlice(pageNumber: pageNum, pageSize: Self.PAGE_SIZE)
//		return getPage(allGetter: {allInventories}, pageNum: pageNum)
	}
	public func getProduct(withHandle handle: String) async -> SHProduct? {
		return productsByID.values.first(where: {$0.handle==handle})
	}
	
	public func getProduct(withID id: Int) async -> SHProduct? {
		return productsByID[id]
	}
	
	public func getIDOfProduct(withHandle handle: String) async -> Int? {
		return await getProduct(withHandle: handle)?.id!
	}
	
	public func updateInventory(current currentGiven: InventoryLevel, update: SHInventorySet) async -> InventoryLevel? {
		guard locations.contains(where: {$0.id == currentGiven.locationID}) else {
			reportError("Location \(currentGiven.locationID) does not exist on store")
			return nil
		}
		guard let locationInventories = inventoriesByLocationIDByInvID[currentGiven.locationID]else{
			reportError("Location \(currentGiven.locationID) is empty!")
			return nil
		}
		guard locationInventories[currentGiven.inventoryItemID] != nil else{
			reportError("Location \(currentGiven.inventoryItemID) does not exist on location \(currentGiven.locationID)")
			return nil
		}
		inventoriesByLocationIDByInvID[currentGiven.locationID]![currentGiven.inventoryItemID]!.available = update.available

		return inventoriesByLocationIDByInvID[currentGiven.locationID]![currentGiven.inventoryItemID]!
	}
	public func updateInventories(currents currentsGiven: [InventoryLevel], updates: [SHInventorySet]) async -> [InventoryLevel]? {
		guard let locID = currentsGiven.randomElement()?.locationID else {reportError("No location ID given!");return nil}
		guard currentsGiven.allSatisfy({$0.locationID == locID}) else {
			reportError("updateInventories only takes updates to the same location ID! Expected all updates to be for location \(locID)")
			return nil
		}
		guard locations.contains(where: {$0.id == locID}) else {
			reportError("Location \(locID) does not exist on store")
			return nil
		}
		guard let locationInventories = inventoriesByLocationIDByInvID[locID]else{
			reportError("Location \(locID) is empty!")
			return nil
		}
		var updated: [InventoryLevel?] = .init(repeating: nil, count: updates.count)
		for i in 0..<updates.count{
			let u = updates[i]
			guard locationInventories[u.inventoryItemID] != nil else{
				reportError("Location \(u.inventoryItemID) does not exist on location \(locID)")
				return nil
			}
			inventoriesByLocationIDByInvID[locID]![u.inventoryItemID]!.available = u.available
			updated[i] = inventoriesByLocationIDByInvID[locID]![u.inventoryItemID]!
		}

		return updated.compactMap{$0}
	}
	
	public func getInventory(of invItemID: Int) async -> InventoryLevel? {
		for (_, invs) in inventoriesByLocationIDByInvID{
			if let found = invs[invItemID]{
				return found
			}
		}
		return nil
	}
	public func getInventories(of invItemIDs: [Int]) async -> [InventoryLevel]? {
		var foundIndices: Set<Int> = .init(minimumCapacity: invItemIDs.count)
		var foundInvs: [InventoryLevel?] = .init(repeating: nil, count: invItemIDs.count)
		for (_, invs) in inventoriesByLocationIDByInvID{
			for i in 0..<invItemIDs.count {
				if foundIndices.contains(i){
					continue
				}
				let invItemID = invItemIDs[i]
				if let found = invs[invItemID]{
					foundInvs[i] = found
					foundIndices.insert(i)
				}
			}
			
		}
		return foundInvs.compactMap{$0}
	}
	
	
	var allInventories: [InventoryLevel] {
		let allCount = inventoriesByLocationIDByInvID.reduce(0){return $0+$1.value.count}
		var arr: [InventoryLevel] = .init()
		arr.reserveCapacity(allCount)
		return inventoriesByLocationIDByInvID.values.reduce(into: arr){
			$0.append(contentsOf: Array($1.values))
		}
	}
	
	public func getAllInventories() async -> [InventoryLevel]? {
		return allInventories
	}
	
	public func getAllInventories(of locationID: Int) async -> [InventoryLevel]? {
		if let val = inventoriesByLocationIDByInvID[locationID]?.values{
			return Array(val)
		}
		return nil
	}
	
	public func getAllLocations() async -> [SHLocation]? {
		return locations
	}
	public enum Resource{
		case products, inventories
	}
	
	
	
	//MARK: Private
	private static func generateNewVariant(variant: SHVariantUpdate, for productID: Int, onLocationID locationID: Int) -> (SHVariant, InventoryLevel){
		let inventoryID = Self.invIDRepo.next()!
		let variantID = Self.variantIDRepo.next()!
		let inventory = InventoryLevel(inventoryItemID: inventoryID, locationID: locationID, updatedAt: formatter.string(from: Date()), adminGraphqlAPIID: "")
		let variant = SHVariant(from: variant, id: variantID, prodID: productID, inventoryItemID: inventoryID)
		return (variant!, inventory)
	}
	func productUpdateHasValidOptions(options: [SHOption], vars: [SHVariantUpdate])->Bool{
		guard options.count <= 3 else {return false}
		let positions = options.compactMap(\.position)
		let uniquePositions = Array(Set(positions))
		guard positions.count == uniquePositions.count else{return false}
		guard positions.allSatisfy({$0>=1 && $0<=3}) else{return false}
		let optionPath: (Int)->KeyPath<SHVariantUpdate,String?>? = {i in
			switch i{
			case 1:
				return \SHVariantUpdate.option1
			case 2:
				return \SHVariantUpdate.option2
			case 3:
				return \SHVariantUpdate.option3
			default:
				return nil
			}
		}
		for i in 0..<options.count{
			guard vars.allSatisfy({$0[keyPath: optionPath(i+1)!] != nil}) else {return false}
		}
		return true
	}
	
	private func reportError(_ msg: String){
		print(msg)
	}
	private func productIDAndIndexOfVariant(variantID: Int)->(Int,Int)?{
		guard let productID = productsByID.first(where: {$0.value.variants.contains(where: {v in v.id == variantID})})?.key else {
			reportError("No variant with id \(variantID)")
			return nil
		}
		let variantIndex = productsByID[productID]!.variants.firstIndex(where: {$0.id == variantID})!
		return (productID,variantIndex)
	}
	
	private func indexOfVariant(productID: Int, variantID: Int)->Int?{
		if let product = productsByID[productID]{
			if let variantIndex = product.variants.firstIndex(where: {$0.id == variantID}){
				return variantIndex
			}
			reportError("product \(productID) has no variant \(variantID)")
		}
		reportError("no product with id \(productID)")
		return nil
	}
	
	
	//MARK: General
	
	
	private func processCurrentAndReturnIfPossible<T: LastUpdated & Hashable>(get: ()async->T?, set: (T)async->()?, _ process: (inout T)async->())async ->T?{
		guard var thing = await get() else {return nil}
		let beforeProcessing = thing
		await process(&thing)
		
		if beforeProcessing != thing {thing.markHasBeenUpdated()}
		
		await set(thing)
		
		return thing
	}
}

func applyUpdate<Entry, Update, T>(on: inout Entry, using: WritableKeyPath<Entry,T?>, from: KeyPath<Update,T?>, from source:Update){
	if let updateProperty = source[keyPath: from]{
		on[keyPath: using] = updateProperty
	}
}
func applyUpdate<Entry, Update, T>(on: inout Entry, using: WritableKeyPath<Entry,T?>, from: KeyPath<Update,T>, from source:Update){
	on[keyPath: using] = source[keyPath: from]
}
func applyUpdate<Entry, Update, T>(on: inout Entry, using: WritableKeyPath<Entry,T>, from: KeyPath<Update,T?>, from source:Update){
	if let updateProperty = source[keyPath: from]{
		on[keyPath: using] = updateProperty
	}
}
func applyUpdate<Entry, Update, T>(on: inout Entry, using: WritableKeyPath<Entry,T>, from: KeyPath<Update,T>, from source:Update){
	on[keyPath: using] = source[keyPath: from]
}
let formatter = ISO8601DateFormatter()
protocol LastUpdated{
	var updatedAtOptional: String? {get set}
}
extension LastUpdated{
	mutating func markHasBeenUpdated(){
		self.updatedAtOptional = formatter.string(from: Date())
	}
}
extension SHVariant: LastUpdated{
	var updatedAtOptional: String?{
		get{updatedAt}
		set{updatedAt=newValue}
	}
}
extension SHProduct: LastUpdated{
	var updatedAtOptional: String?{
		get{updatedAt}
		set{updatedAt=newValue}
	}
}
extension SHLocation: LastUpdated{
	var updatedAtOptional: String?{
		get{updatedAt}
		set{if let newValue{updatedAt=newValue}}
	}
}
extension InventoryLevel: LastUpdated{
	var updatedAtOptional: String?{
		get{updatedAt}
		set{if let newValue{updatedAt=newValue}}
	}
}
extension SHVariant{
	mutating func applyUpdate(from update: SHVariantUpdate){
		func applyUpdate<T>(using: WritableKeyPath<SHVariant,T>, from: KeyPath<SHVariantUpdate,T?>){
			App.applyUpdate(on: &self, using: using, from: from, from: update)
		}
		func applyUpdate<T>(using: WritableKeyPath<SHVariant,T?>, from: KeyPath<SHVariantUpdate,T?>){
			App.applyUpdate(on: &self, using: using, from: from, from: update)
		}
		applyUpdate(using: \.title, from: \.title)
		applyUpdate(using: \.option1, from: \.option1)
		applyUpdate(using: \.option2, from: \.option2)
		applyUpdate(using: \.option3, from: \.option3)
		applyUpdate(using: \.barcode, from: \.barcode)
		applyUpdate(using: \.compareAtPrice, from: \.compare_at_price)
		applyUpdate(using: \.price, from: \.price)
		applyUpdate(using: \.sku, from: \.sku)
	}
}
extension SHVariant{
	init?(from: SHVariantUpdate, id: Int, prodID: Int, inventoryItemID: Int){
		guard let sku=from.sku else {return nil}
		self.init(id: id, productID: prodID, title: from.title ?? "default", price: from.price ?? "0", sku: sku, position: nil, inventoryPolicy: ._continue, compareAtPrice: from.compare_at_price, fulfillmentService: .manual, inventoryManagement: nil, option1: from.option1, option2: from.option2, option3: from.option3, createdAt: formatter.string(from: Date()), updatedAt: formatter.string(from: Date()), taxable: true, barcode: from.barcode, grams: nil, imageID: nil, weight: nil, weightUnit: nil, inventoryItemID: inventoryItemID, inventoryQuantity: nil, oldInventoryQuantity: nil, requiresShipping: nil, adminGraphqlAPIID: nil, inventoryLevel: nil)
	}
}
extension SHVariantUpdate{
	func numberOfOptions()->Int{
		var count = 0
		
		count += option1 != nil ? 1 : 0
		count += option2 != nil ? 1 : 0
		count += option3 != nil ? 1 : 0
		
		return count
	}
}
extension Array where Element == SHOption{
	mutating func applyUpdate(from update: Self, productID: Int){
		for optionUpdate in update{
			if let id = optionUpdate.id, let indexOfExisting = self.firstIndex(where: {$0.id == id}){
				App.applyUpdate(on: &self[indexOfExisting], using: \.position, from: \.position, from: optionUpdate)
				App.applyUpdate(on: &self[indexOfExisting], using: \.name, from: \.name, from: optionUpdate)
				App.applyUpdate(on: &self[indexOfExisting], using: \.values, from: \.values, from: optionUpdate)
			}else{
				let new = SHOption(id: Int.random(), productID: productID, name: optionUpdate.name, position: optionUpdate.position, values: optionUpdate.values)
				append(new)
			}
		}
	}
}
extension SHOption{
	mutating func applyUpdate(from: SHOption){
		
	}
}
