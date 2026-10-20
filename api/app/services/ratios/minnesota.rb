# Minnesota licensed child care center ratios and group sizes, Minn. R. 9503.0040.
# Categories by age (9503.0005): infant 6 weeks to 16 months, toddler 16 to 33 months,
# preschooler 33 months to kindergarten, school age after that. A mixed group uses the
# category of the youngest child present. Only staff working directly with children count.
#
# Known simplifications (prior-art record D14): kindergarteners are not modeled separately,
# the 18-month infant extension is ignored, and group size waivers for meals, naps and outdoor
# time are not applied, so this errs on the strict side.
module Ratios
  module Minnesota
    Category = Data.define(:name, :ratio, :max_group)

    INFANT = Category.new(name: "infant", ratio: 4, max_group: 8)
    TODDLER = Category.new(name: "toddler", ratio: 7, max_group: 14)
    PRESCHOOLER = Category.new(name: "preschooler", ratio: 10, max_group: 20)
    SCHOOL_AGE = Category.new(name: "school_age", ratio: 15, max_group: 30)

    module_function

    def category_for(age_months)
      if age_months < 16 then INFANT
      elsif age_months < 33 then TODDLER
      elsif age_months < 72 then PRESCHOOLER
      else SCHOOL_AGE
      end
    end
  end
end
