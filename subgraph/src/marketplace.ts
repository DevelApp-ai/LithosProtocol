import { BigInt, Address, Bytes } from "@graphprotocol/graph-ts"
import {
  ItemListed,
  ItemSold,
  ItemDelisted,
  BidPlaced,
  AuctionEnded
} from "../generated/Marketplace/Marketplace"
import {
  User,
  Listing,
  Sale,
  Bid,
  Asset,
  GlobalStats
} from "../generated/schema"

export function handleItemListed(event: ItemListed): void {
  let seller = getOrCreateUser(event.params.seller)
  
  // Create listing
  let listing = new Listing(event.params.listingId.toString())
  listing.listingId = event.params.listingId
  listing.seller = seller.id
  listing.nftContract = event.params.nftContract
  listing.tokenId = event.params.tokenId
  listing.amount = event.params.amount
  listing.assetType = event.params.listingType == 0 ? "ERC721" : "ERC1155"
  listing.listingType = event.params.listingType == 0 ? "FIXED_PRICE" : "AUCTION"
  listing.paymentToken = Bytes.empty() // Would need to get from contract call
  listing.price = event.params.price
  listing.endTime = BigInt.fromI32(0) // Would need to get from contract call
  listing.isActive = true
  listing.highestBid = BigInt.fromI32(0)
  listing.createdAt = event.block.timestamp
  listing.updatedAt = event.block.timestamp
  listing.save()
  
  // Link to asset if it exists
  let assetId = event.params.nftContract.toHexString() + "-" + event.params.tokenId.toString()
  let asset = Asset.load(assetId)
  if (asset != null) {
    listing.asset = asset.id
    listing.save()
  }
  
  // Update seller
  seller.updatedAt = event.block.timestamp
  seller.save()
  
  // Update global stats
  let globalStats = getOrCreateGlobalStats()
  globalStats.totalListings = globalStats.totalListings.plus(BigInt.fromI32(1))
  globalStats.updatedAt = event.block.timestamp
  globalStats.save()
}

export function handleItemSold(event: ItemSold): void {
  let seller = getOrCreateUser(event.params.seller)
  let buyer = getOrCreateUser(event.params.buyer)
  
  let listing = Listing.load(event.params.listingId.toString())
  if (listing == null) {
    return
  }
  
  // Create sale
  let saleId = event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  let sale = new Sale(saleId)
  sale.listing = listing.id
  sale.seller = seller.id
  sale.buyer = buyer.id
  sale.price = event.params.price
  sale.fee = event.params.fee
  sale.transactionHash = event.transaction.hash
  sale.blockNumber = event.block.number
  sale.timestamp = event.block.timestamp
  
  // Link to asset if it exists
  if (listing.asset != null) {
    sale.asset = listing.asset!
  }
  
  sale.save()
  
  // Update listing
  listing.isActive = false
  listing.updatedAt = event.block.timestamp
  listing.save()
  
  // Update users
  seller.updatedAt = event.block.timestamp
  seller.save()
  
  buyer.updatedAt = event.block.timestamp
  buyer.save()
  
  // Update asset owner if it exists
  if (listing.asset != null) {
    let asset = Asset.load(listing.asset!)
    if (asset != null) {
      asset.owner = buyer.id
      asset.updatedAt = event.block.timestamp
      asset.save()
    }
  }
  
  // Update global stats
  let globalStats = getOrCreateGlobalStats()
  globalStats.totalSales = globalStats.totalSales.plus(BigInt.fromI32(1))
  globalStats.totalVolume = globalStats.totalVolume.plus(event.params.price)
  globalStats.updatedAt = event.block.timestamp
  globalStats.save()
}

export function handleItemDelisted(event: ItemDelisted): void {
  let seller = getOrCreateUser(event.params.seller)
  
  let listing = Listing.load(event.params.listingId.toString())
  if (listing == null) {
    return
  }
  
  // Update listing
  listing.isActive = false
  listing.updatedAt = event.block.timestamp
  listing.save()
  
  // Update seller
  seller.updatedAt = event.block.timestamp
  seller.save()
}

export function handleBidPlaced(event: BidPlaced): void {
  let bidder = getOrCreateUser(event.params.bidder)
  
  let listing = Listing.load(event.params.listingId.toString())
  if (listing == null) {
    return
  }
  
  // Create bid
  let bidId = event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  let bid = new Bid(bidId)
  bid.listing = listing.id
  bid.bidder = bidder.id
  bid.amount = event.params.amount
  bid.transactionHash = event.transaction.hash
  bid.blockNumber = event.block.number
  bid.timestamp = event.block.timestamp
  bid.save()
  
  // Update listing with highest bid
  listing.highestBidder = bidder.id
  listing.highestBid = event.params.amount
  listing.updatedAt = event.block.timestamp
  listing.save()
  
  // Update bidder
  bidder.updatedAt = event.block.timestamp
  bidder.save()
}

export function handleAuctionEnded(event: AuctionEnded): void {
  let listing = Listing.load(event.params.listingId.toString())
  if (listing == null) {
    return
  }
  
  // Update listing
  listing.isActive = false
  listing.updatedAt = event.block.timestamp
  listing.save()
  
  // If there was a winner, create a sale
  if (event.params.winner.toHexString() != "0x0000000000000000000000000000000000000000") {
    let winner = getOrCreateUser(event.params.winner)
    let seller = User.load(listing.seller)
    
    if (seller != null) {
      let saleId = event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
      let sale = new Sale(saleId)
      sale.listing = listing.id
      sale.seller = seller.id
      sale.buyer = winner.id
      sale.price = event.params.winningBid
      sale.fee = BigInt.fromI32(0) // Would need to calculate from price and fee rate
      sale.transactionHash = event.transaction.hash
      sale.blockNumber = event.block.number
      sale.timestamp = event.block.timestamp
      
      // Link to asset if it exists
      if (listing.asset != null) {
        sale.asset = listing.asset!
        
        // Update asset owner
        let asset = Asset.load(listing.asset!)
        if (asset != null) {
          asset.owner = winner.id
          asset.updatedAt = event.block.timestamp
          asset.save()
        }
      }
      
      sale.save()
      
      // Update users
      seller.updatedAt = event.block.timestamp
      seller.save()
      
      winner.updatedAt = event.block.timestamp
      winner.save()
      
      // Update global stats
      let globalStats = getOrCreateGlobalStats()
      globalStats.totalSales = globalStats.totalSales.plus(BigInt.fromI32(1))
      globalStats.totalVolume = globalStats.totalVolume.plus(event.params.winningBid)
      globalStats.updatedAt = event.block.timestamp
      globalStats.save()
    }
  }
}

function getOrCreateUser(address: Address): User {
  let user = User.load(address.toHexString())
  
  if (user == null) {
    user = new User(address.toHexString())
    user.governanceTokenBalance = BigInt.fromI32(0)
    user.utilityTokenBalance = BigInt.fromI32(0)
    user.votingPower = BigInt.fromI32(0)
    user.isRegistered = false
    user.level = BigInt.fromI32(0)
    user.experience = BigInt.fromI32(0)
    user.pvpWins = BigInt.fromI32(0)
    user.pvpLosses = BigInt.fromI32(0)
    user.lastDailyQuestClaim = BigInt.fromI32(0)
    user.createdAt = BigInt.fromI32(0)
    user.updatedAt = BigInt.fromI32(0)
    
    // Update global stats
    let globalStats = getOrCreateGlobalStats()
    globalStats.totalUsers = globalStats.totalUsers.plus(BigInt.fromI32(1))
    globalStats.save()
  }
  
  return user
}

function getOrCreateGlobalStats(): GlobalStats {
  let globalStats = GlobalStats.load("global")
  
  if (globalStats == null) {
    globalStats = new GlobalStats("global")
    globalStats.totalGovernanceTokenSupply = BigInt.fromI32(0)
    globalStats.totalUtilityTokenSupply = BigInt.fromI32(0)
    globalStats.totalUsers = BigInt.fromI32(0)
    globalStats.totalPlayers = BigInt.fromI32(0)
    globalStats.totalAssets = BigInt.fromI32(0)
    globalStats.totalResources = BigInt.fromI32(0)
    globalStats.totalListings = BigInt.fromI32(0)
    globalStats.totalSales = BigInt.fromI32(0)
    globalStats.totalVolume = BigInt.fromI32(0)
    globalStats.totalStakingPools = BigInt.fromI32(0)
    globalStats.totalStaked = BigInt.fromI32(0)
    globalStats.totalRewardsDistributed = BigInt.fromI32(0)
    globalStats.totalQuests = BigInt.fromI32(0)
    globalStats.totalQuestCompletions = BigInt.fromI32(0)
    globalStats.totalPvPMatches = BigInt.fromI32(0)
    globalStats.totalItemsCrafted = BigInt.fromI32(0)
    globalStats.updatedAt = BigInt.fromI32(0)
  }
  
  return globalStats
}

