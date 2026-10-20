class DomainEvent < ApplicationRecord
  scope :for_center, ->(center) { where(center_id: center.id) }
end
