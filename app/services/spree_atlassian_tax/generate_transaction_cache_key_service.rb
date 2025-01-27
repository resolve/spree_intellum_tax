module SpreeAtlassianTax
  class GenerateTransactionCacheKeyService < SpreeAtlassianTax::Base
    def call(order:)
      reloaded_order = order.class.includes(
        :line_items,
        :adjustments,
        :shipments               => :stock_location,
        order.tax_address_symbol => %i[state country]
      ).find(order.id)

      success(transaction_cache_key(reloaded_order))
    end

    private

    def transaction_cache_key(order)
      transaction_cache_key = [
        order_cache_key(order),
        tax_address_cache_key(order.tax_address),
        line_items_cache_key(order),
        shipments_cache_key(order.shipments),
        atlassian_preferences_cache_key(order)
      ].join('-')

      # Cache key length has to be compressed as max_length is 250:
      # https://github.com/memcached/memcached/blob/master/memcached.h#L36
      "atlassian-transaction-#{Digest::MD5.hexdigest(transaction_cache_key)}"
    end

    def order_cache_key(order)
      [
        order.number,
        order.atlassian_discount_amount
      ].join('-')
    end

    def tax_address_cache_key(tax_address)
      [
        tax_address.address1,
        tax_address.address2,
        tax_address.city,
        tax_address.state.try(:abbr),
        tax_address.country.try(:iso),
        tax_address.zipcode
      ].join('-')
    end

    def line_items_cache_key(order) # rubocop:disable Metrics/MethodLength
      order.line_items.map do |line_item|
        [
          line_item.atlassian_uuid,
          line_item.quantity,
          line_item.variant_id,
          line_item.price,
          line_item.amount,
          line_item.discounted_amount,
          order.line_items_discounted_in_atlassian?,
          line_item.atlassian_tax_code
        ].join('-')
      end.join('-')
    end

    def shipments_cache_key(shipments)
      shipments.map do |shipment|
        [
          shipment.atlassian_uuid,
          shipment.discounted_cost,
          shipment.atlassian_tax_code,
          stock_location_cache_key(shipment.stock_location)
        ].join('-')
      end.join('-')
    end

    def stock_location_cache_key(stock_location)
      [
        stock_location.address1,
        stock_location.address2,
        stock_location.city,
        stock_location.state.try(:abbr),
        stock_location.country.try(:iso)
      ].join('-')
    end

    def atlassian_preferences_cache_key(order)
      ship_from_address_timestamp = ship_from_address_preference.try(:updated_at).try(:utc).try(:to_s, :number)

      "#{company_code(order)}-#{ship_from_address_timestamp}"
    end

    def ship_from_address_preference
      ::Spree::Preference.find_by(key: 'spree_atlassian_tax/configuration/ship_from_address')
    end
  end
end
