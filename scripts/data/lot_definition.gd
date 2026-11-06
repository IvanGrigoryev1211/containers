extends Resource
class_name LotDefinition

## Auction-lot data. S03 uses typical_winning_price as the fixed rival threshold
## and settlement price; bid_limit is the maximum allowed player limit.
@export var id := ""
@export var display_name := ""
@export var start_price := 0
@export var bid_limit := 0
@export var typical_winning_price := 0
@export var guaranteed_price_floor := 0
@export var visible_evidence: Array[EvidenceDefinition] = []
@export var future_items: Array[ItemDefinition] = []
@export_multiline var designer_notes := ""
