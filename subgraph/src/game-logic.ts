import { BigInt, Address, Bytes } from "@graphprotocol/graph-ts"
import {
  PlayerRegistered,
  QuestCompleted,
  PvPResult,
  ItemCrafted,
  ExperienceGained
} from "../generated/GameLogic/GameLogic"
import {
  User,
  Player,
  Quest,
  QuestCompletion,
  PvPMatch,
  CraftingEvent,
  Asset,
  GlobalStats
} from "../generated/schema"

export function handlePlayerRegistered(event: PlayerRegistered): void {
  let user = getOrCreateUser(event.params.player)
  
  // Create player entity
  let player = new Player(event.params.player.toHexString())
  player.user = user.id
  player.level = BigInt.fromI32(1)
  player.experience = BigInt.fromI32(0)
  player.pvpWins = BigInt.fromI32(0)
  player.pvpLosses = BigInt.fromI32(0)
  player.lastDailyQuestClaim = BigInt.fromI32(0)
  player.isActive = true
  player.registeredAt = event.block.timestamp
  player.updatedAt = event.block.timestamp
  player.save()
  
  // Update user
  user.isRegistered = true
  user.level = BigInt.fromI32(1)
  user.experience = BigInt.fromI32(0)
  user.pvpWins = BigInt.fromI32(0)
  user.pvpLosses = BigInt.fromI32(0)
  user.lastDailyQuestClaim = BigInt.fromI32(0)
  user.updatedAt = event.block.timestamp
  user.save()
  
  // Update global stats
  let globalStats = getOrCreateGlobalStats()
  globalStats.totalPlayers = globalStats.totalPlayers.plus(BigInt.fromI32(1))
  globalStats.updatedAt = event.block.timestamp
  globalStats.save()
}

export function handleQuestCompleted(event: QuestCompleted): void {
  let user = getOrCreateUser(event.params.player)
  let player = Player.load(event.params.player.toHexString())
  
  if (player == null) {
    player = new Player(event.params.player.toHexString())
    player.user = user.id
    player.level = BigInt.fromI32(1)
    player.experience = BigInt.fromI32(0)
    player.pvpWins = BigInt.fromI32(0)
    player.pvpLosses = BigInt.fromI32(0)
    player.lastDailyQuestClaim = BigInt.fromI32(0)
    player.isActive = true
    player.registeredAt = event.block.timestamp
  }
  
  // Create quest completion
  let completionId = event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  let completion = new QuestCompletion(completionId)
  completion.quest = event.params.questId.toString()
  completion.player = player.id
  completion.reward = event.params.reward
  completion.transactionHash = event.transaction.hash
  completion.blockNumber = event.block.number
  completion.timestamp = event.block.timestamp
  completion.save()
  
  // Update player
  player.updatedAt = event.block.timestamp
  player.save()
  
  // Update user utility token balance (reward received)
  user.utilityTokenBalance = user.utilityTokenBalance.plus(event.params.reward)
  user.updatedAt = event.block.timestamp
  user.save()
  
  // Update global stats
  let globalStats = getOrCreateGlobalStats()
  globalStats.totalQuestCompletions = globalStats.totalQuestCompletions.plus(BigInt.fromI32(1))
  globalStats.updatedAt = event.block.timestamp
  globalStats.save()
}

export function handlePvPResult(event: PvPResult): void {
  let winner = getOrCreateUser(event.params.winner)
  let loser = getOrCreateUser(event.params.loser)
  
  let winnerPlayer = Player.load(event.params.winner.toHexString())
  let loserPlayer = Player.load(event.params.loser.toHexString())
  
  if (winnerPlayer == null) {
    winnerPlayer = new Player(event.params.winner.toHexString())
    winnerPlayer.user = winner.id
    winnerPlayer.level = BigInt.fromI32(1)
    winnerPlayer.experience = BigInt.fromI32(0)
    winnerPlayer.pvpWins = BigInt.fromI32(0)
    winnerPlayer.pvpLosses = BigInt.fromI32(0)
    winnerPlayer.lastDailyQuestClaim = BigInt.fromI32(0)
    winnerPlayer.isActive = true
    winnerPlayer.registeredAt = event.block.timestamp
  }
  
  if (loserPlayer == null) {
    loserPlayer = new Player(event.params.loser.toHexString())
    loserPlayer.user = loser.id
    loserPlayer.level = BigInt.fromI32(1)
    loserPlayer.experience = BigInt.fromI32(0)
    loserPlayer.pvpWins = BigInt.fromI32(0)
    loserPlayer.pvpLosses = BigInt.fromI32(0)
    loserPlayer.lastDailyQuestClaim = BigInt.fromI32(0)
    loserPlayer.isActive = true
    loserPlayer.registeredAt = event.block.timestamp
  }
  
  // Create PvP match
  let matchId = event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  let match = new PvPMatch(matchId)
  match.winner = winnerPlayer.id
  match.loser = loserPlayer.id
  match.participants = [winnerPlayer.id, loserPlayer.id]
  match.reward = event.params.reward
  match.transactionHash = event.transaction.hash
  match.blockNumber = event.block.number
  match.timestamp = event.block.timestamp
  match.save()
  
  // Update winner stats
  winnerPlayer.pvpWins = winnerPlayer.pvpWins.plus(BigInt.fromI32(1))
  winnerPlayer.updatedAt = event.block.timestamp
  winnerPlayer.save()
  
  winner.pvpWins = winner.pvpWins.plus(BigInt.fromI32(1))
  winner.utilityTokenBalance = winner.utilityTokenBalance.plus(event.params.reward)
  winner.updatedAt = event.block.timestamp
  winner.save()
  
  // Update loser stats
  loserPlayer.pvpLosses = loserPlayer.pvpLosses.plus(BigInt.fromI32(1))
  loserPlayer.updatedAt = event.block.timestamp
  loserPlayer.save()
  
  loser.pvpLosses = loser.pvpLosses.plus(BigInt.fromI32(1))
  loser.updatedAt = event.block.timestamp
  loser.save()
  
  // Update global stats
  let globalStats = getOrCreateGlobalStats()
  globalStats.totalPvPMatches = globalStats.totalPvPMatches.plus(BigInt.fromI32(1))
  globalStats.updatedAt = event.block.timestamp
  globalStats.save()
}

export function handleItemCrafted(event: ItemCrafted): void {
  let user = getOrCreateUser(event.params.player)
  let player = Player.load(event.params.player.toHexString())
  
  if (player == null) {
    player = new Player(event.params.player.toHexString())
    player.user = user.id
    player.level = BigInt.fromI32(1)
    player.experience = BigInt.fromI32(0)
    player.pvpWins = BigInt.fromI32(0)
    player.pvpLosses = BigInt.fromI32(0)
    player.lastDailyQuestClaim = BigInt.fromI32(0)
    player.isActive = true
    player.registeredAt = event.block.timestamp
  }
  
  // Create crafting event
  let craftingId = event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  let craftingEvent = new CraftingEvent(craftingId)
  craftingEvent.player = player.id
  craftingEvent.asset = event.params.tokenId.toString() // This will be linked when asset is created
  craftingEvent.cost = event.params.cost
  craftingEvent.resourcesUsed = [] // Would need additional event data
  craftingEvent.resourceAmounts = [] // Would need additional event data
  craftingEvent.transactionHash = event.transaction.hash
  craftingEvent.blockNumber = event.block.number
  craftingEvent.timestamp = event.block.timestamp
  craftingEvent.save()
  
  // Update player
  player.updatedAt = event.block.timestamp
  player.save()
  
  // Update user (crafting cost deducted)
  user.utilityTokenBalance = user.utilityTokenBalance.minus(event.params.cost)
  user.updatedAt = event.block.timestamp
  user.save()
  
  // Update global stats
  let globalStats = getOrCreateGlobalStats()
  globalStats.totalItemsCrafted = globalStats.totalItemsCrafted.plus(BigInt.fromI32(1))
  globalStats.updatedAt = event.block.timestamp
  globalStats.save()
}

export function handleExperienceGained(event: ExperienceGained): void {
  let user = getOrCreateUser(event.params.player)
  let player = Player.load(event.params.player.toHexString())
  
  if (player == null) {
    player = new Player(event.params.player.toHexString())
    player.user = user.id
    player.level = BigInt.fromI32(1)
    player.experience = BigInt.fromI32(0)
    player.pvpWins = BigInt.fromI32(0)
    player.pvpLosses = BigInt.fromI32(0)
    player.lastDailyQuestClaim = BigInt.fromI32(0)
    player.isActive = true
    player.registeredAt = event.block.timestamp
  }
  
  // Update player experience and level
  player.experience = player.experience.plus(event.params.amount)
  player.level = event.params.newLevel
  player.updatedAt = event.block.timestamp
  player.save()
  
  // Update user
  user.experience = user.experience.plus(event.params.amount)
  user.level = event.params.newLevel
  user.updatedAt = event.block.timestamp
  user.save()
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
    user.createdAt = BigInt.fromI32(0) // Will be updated when first seen
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

