//
//  Extensions.swift
//  
//
//  Created by Andreas Loizides on 18/03/2023.
//

import Foundation
extension Array{
	public func getPaginatedSlice(pageNumber: Int, pageSize: Int) -> [Element]? {
		guard pageNumber>0 else {return nil}
		
		let indexOffset = (pageNumber-1)*pageSize
		guard indexOffset>=0 else {return nil}
		
		let lastReachableIndex = self.count-1
		let lastWantedIndex = Swift.min(lastReachableIndex, indexOffset+pageSize-1)
		assert(indexOffset<=lastWantedIndex)
		let slice = self[indexOffset...lastWantedIndex]
		return Array(slice)
		
		
		/**
		 page 1:
		 start	end
		 item0	item99
		 itemsToSkip: 0
		 
		 page2:
		 start	end
		 item100	item199
		 itemsToSkip: 100 ([0]->[99])
		 
		 page 3:
		 start	end
		 item200	item299
		 itemsToSkip: 200([0]->[199])
		 
		 page n:
		 start			end
		 item[(n-1)*100]	item[(n-1)*100+99]
		 itemsToSkip: (n-1)*100
		 */
	}
}
