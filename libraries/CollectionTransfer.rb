# Cannon Mallory
# malloc3@uw.edu
#
# Methods for transferring items into and out of collections

needs 'Standard Libs/Units'
needs 'Standard Libs/Debug'
needs 'Standard Libs/AssociationManagement'
needs 'Collection_Management/CollectionLocation'
needs 'Collection_Management/CollectionData'

module CollectionTransfer
  include Units
  include Debug
  include AssociationManagement
  include CollectionLocation
  include CollectionData

  VOL_TRANSFER = 'Volume Transferred'.to_sym

  # gets the number of plates
  #
  # @param operations [OperationList] list of operations in job
  # @param role [String] indicates whether it's an input or output collection
  # @returns Array[collection] the number of plates
  def get_array_of_collections(operations, role)
    collection_array = []
    operations.each do |op|
      obj_array = op.inputs if role == 'input'
      obj_array = op.outputs if role == 'output'
      obj_array.each do |fv|
        collection_array.push(fv.collection) unless fv.collection.nil?
      end
    end
    collection_array.uniq
  end

  # Determines if there are multiple plates
  #
  # @param operations [OperationList] list of operations in job
  # @param role [String], whether plates are for input or output
  # @returns boolean true if multiple plates
  def multiple_plates?(operations, role: 'input')
    return true if get_num_plates(operations, role) > 1
  end

  # gets the number of plates
  #
  # @param operations [OperationList] list of operations in job
  # @param role [String] indicates whether it's an input or output collection
  # @returns [Int] the number of plates
  def get_num_plates(operations, role)
    get_array_of_collections(operations, role).length
  end



  # Transfers samples from fv_array to collection.  If the collection cannot
  # hold all the samples it will create more collections to hold all samples.
  # Will automatically populate the collection
  #
  # fv_array can be of items in collections or not doesn't matter
  #
  #
  # Optional: Can provide instructions for transferring samples to collections
  #
  # Samples can be either FieldValue or Item/Part
  # Groups samples by collection for easier transfer
  # Uses transfer_to_to_collection method
  #
  # @param input_fv_array [Array<FieldValues>] an array of field values
  # @param to_collection [Collection] Should have samples already associated
  # @param transfer_vol [Int] volume in sample to transfer
  def transfer_subsamples_to_working_plate(fv_array, to_collection: nil, 
                                      collection_type: nil, transfer_vol: nil,
                                      instructions: true, add_column_wise: false)

    grouped_fv_array = fv_array.group_by{|fv| fv.part?}
    collections = []
    grouped_fv_array.each do |is_part, sub_fv_array|
      if is_part
        collections += transfer_collection_to_collection(sub_fv_array, 
                                        to_collection: to_collection,
                                        collection_type: collection_type,
                                        transfer_vol: transfer_vol,
                                        instructions: instructions,
                                        add_column_wise: add_column_wise)
      else
        collections += transfer_items_to_collection(sub_fv_array, 
                                          to_collection: to_collection,
                                          collection_type: collection_type,
                                          transfer_vol: transfer_vol,
                                          instructions: instructions,
                                          add_column_wise: add_column_wise)
      end
    end
    collections.uniq
  end


  # Handles transfers of items from one collection to another collection
  #
  # If an 'association_map' is given 'to_collection' must also be given
  #  it will assume that the plate is already plated.
  #  'array_of_samples', 'one_to_one', and 'populate_collection' will be ignored
  #
  # If array_of_samples is not given then it will be assumed that all samples
  #   should transferred.
  # 
  #
  # @param input_collection [Collection] the collection samples come from
  # @param to_collection[Collection] the collection samples will move to
  # @param transfer_vol [String] volume of sample to transfer (INCLUDE UNITS)
  # @param populate_collection [Boolean] true if the to_collection needs to be
  #        populated false if the to_collection has already been populated.
  # @param array_of_samples [Array<Sample>] Optional
  # @param instructions [Boolean] default true to include instructions
  # @param association_map [Array<{to_loc: [r, c], from_loc: [r, c]}, ...>]
  #        a map showing the associations from one collection to another.
  def transfer_from_collection_to_collection(from_collection, 
                                             to_collection: nil,
                                             collection_type: nil,
                                             transfer_vol: nil,
                                             populate_collection: true,
                                             array_of_samples: nil,
                                             instructions: true,
                                             one_to_one: false,
                                             association_map: nil,
                                             column_wise: false)
    collections, association_maps = determine_collections_and_association_map(from_collection, 
                                                                to_collection: to_collection,
                                                                collection_type: collection_type,
                                                                populate_collection: populate_collection,
                                                                array_of_samples: array_of_samples,
                                                                instructions: instructions,
                                                                one_to_one: one_to_one,
                                                                association_map: association_map,
                                                                add_column_wise: column_wise)

    collections.each_with_index do |collection, idx|
      association_map = association_maps[idx]
      associate_plate_to_plate(to_collection: collection, from_collection: from_collection,
                              association_map: association_map, transfer_vol: transfer_vol)
      if instructions
        collection_to_collection_transfer_instructions(to_collection: collection, from_collection: from_collection,
                                       association_map: association_map, transfer_vol: transfer_vol)
      end
    end
    collections
  end



  # TODO Break this apart
  # Assists with transfer of items into a collection
  # Optional Instructions to tech
  #
  # @param fv_array [Array<item or field values>] the samples to be transferred
  #
  # @param to_collection [Collection] (optional)
  # @param collection_type [String] (optional)
  #    NOTE: exactly one to_collection or collection_type must be given
  #
  # @param transfer_volume [Float] the volume that is to be transferred
  # @param instructions [Boolean] true if instructions are to be displayed
  #

  # @param association_map [Array<{to_loc: [row, col], from_loc: item},...>]
  #        if a map is given then the plate is assumed to be populated already
  #
  # @return collections [Array<Collections>] the collections created/used
  def transfer_items_to_collection(fv_array, to_collection: nil,
                                             collection_type: nil,
                                             transfer_vol: nil,
                                             instructions: true,
                                             association_map: nil,
                                             add_column_wise: false)
    sample_array = fv_array.map(&:sample)
    array_of_association_maps = []
    collections = []

    if association_map.nil?
      collections = make_and_populate_collection(sample_array,
                                            first_collection: to_collection,
                                            collection_type: collection_type,
                                            label_plates: instructions,
                                            add_column_wise: add_column_wise)
      collections.each do |collection|
        association_map = make_item_to_collection_association_map(sample_array,
                                                        collection: collection)
        array_of_association_maps.push(association_map)
      end
    else
      ProtocolError 'Must Give to_collection' if to_collection.nil?
      array_of_association_maps.push(association_map)
      collections.push(to_collection)
    end

    array_of_association_maps.each_with_index do |map, idx|
      collection = collections[idx]
      associate_items_to_wells(to_collection: collection, association_map: map,
                                                    transfer_vol: transfer_vol)
      next unless instructions


      item_to_collection_transfer_instructions(to_collection: collection,
                                               association_map: map,
                                               transfer_vol: transfer_vol)
    end
    collections
  end

  # Assist with the transfer from a collection to an item.
  # An association map must first be created
  #

  # @param from_collection [Collection] the collection that is being transferred
  # @param association_map [Array<{to_loc: item, from_loc: [row, col]}, ...>]
  # @param transfer_vol [String/Int] the volume being transferred
  # @param instructions [Boolean] optional instructions
  def transfer_from_collection_to_items(from_collection:, association_map:,
                                                          transfer_vol: nil,
                                                          instructions: true)
    associate_wells_to_item(from_collection: from_collection, association_map: association_map,
                            transfer_vol: transfer_vol)
    next unless instructions

    collection_to_items_transfer_instructions(from_collection: from_collection,
                                              association_map: association_map,
                                              transfer_vol: transfer_vol)
  end

  # Instructions on relabeling plates to new plate ID
  # Tracks provenance properly though transfer
  #
  # @param plate1 [Collection] plate to relabel
  # @param plate2 [Collection] new plate label
  def relabel_plate(from_collection, to_collection: nil)
    collection_type = nil

    collection_type = from_collection.object_type.name if to_collection.nil?

    unless from_collection.object_type == to_collection.object_type
      ProtocolError 'Object Types do not match'
    end

    relabeled_collection = transfer_from_collection_to_collection(from_collection,
                                                to_collection: to_collection,
                                                collection_type: collection_type,
                                                instructions: false,
                                                one_to_one: true,
                                                add_column_wise: false).first
    show do
      title 'Rename Plate'
      note "Relabel plate <b>#{from_collection.id}</b> with
                        <b>#{relabeled_collection.id}</b>"
    end
    to_collection
  end


  # To offload work from transfer_from_collection_to_collection
  # Handles large if else cases and returns collections and association maps
  def determine_collections_and_association_map(from_collection, 
                                                to_collection: nil,
                                                collection_type: nil,
                                                populate_collection: true,
                                                array_of_samples: nil,
                                                instructions: true,
                                                one_to_one: false,
                                                association_map: nil,
                                                add_column_wise: false)
    association_maps = []
    collections = []
    if !association_map.nil?
      raise 'to_collection not given' if to_collection.nil?

      collections.push(to_collection)
      association_maps.push(association_map)
    elsif one_to_one
      unless array_of_samples.nil?
        raise 'array_of_samples cannot ge given if one_to_one'
      end


      if populate_collection || to_collection.nil?
        # TODO this may not work as expected....  need to think about this
        array_of_samples = get_samples_from_obj(from_collection.parts)

        collections = make_and_populate_collection(array_of_samples, 
                                                first_collection: to_collection,
                                                collection_type: collection_type,
                                                label_plate: instructions,
                                                add_column_wise: false)
      else
        collections = [to_collection]
      end
      association_map = make_one_to_many_association_map(
                                                  to_collection: collection,
                                                  from_collection: from_collection,
                                                  samples: nil,
                                                  one_to_one: true)
      association_maps.push(association_map)
    else
      if array_of_samples.nil?
        array_of_samples = get_samples_from_obj(from_collection.parts)
      end


      array_of_samples.map! do |object| 
        if object.is_a? Sample
          object
        else
          object = object.sample
        end
      end      
      if populate_collection || to_collection.nil?
        collections = make_and_populate_collection(array_of_samples, 
                                                first_collection: to_collection,
                                                collection_type: collection_type,
                                                label_plates: instructions)
      else
        collections = [to_collection]
      end

      collections.each do |collection|
        association_map = make_one_to_many_association_map(
                                            to_collection: collection,
                                            from_collection: from_collection,
                                            samples: array_of_samples,
                                            one_to_one: one_to_one)
        association_maps.push(association_map)
      end
    end
    [collections, association_maps]
  end

  def get_samples_from_obj(array)
    array.map do |part|
      return part.sample unless part.is_a? Sample

      part
    end
    array
  end

  # @warning Use transfer_subsamples_to_working_plate instead
  #
  # @param fv_array Array<FieldValues>] an array of field values of collections
  # @param to_collection [Collection]
  # @param transfer_vol [String/Int] volume in sample to transfer
  # @param instructions [Boolean] true if instructions are to be shown
  def transfer_collection_to_collection(fv_array, to_collection: nil, 
                                                  collection_type: nil, 
                                                  transfer_vol: nil,
                                                  instructions: nil, 
                                                  add_column_wise: false)
    collections = []
    sample_array_by_collection = fv_array.group_by { |fv| fv.collection }
    sample_array_by_collection.each do |from_collection, fv_array|
      sample_array = fv_array.map { |fv| fv.sample }
      collections = transfer_from_collection_to_collection(from_collection, 
                                               to_collection: to_collection,
                                               collection_type: collection_type,
                                               transfer_vol: transfer_vol,
                                               array_of_samples: sample_array,
                                               instructions: instructions)
    end
    collections
  end


  # Transfer instructions for tech
  #

  # @param to_collection [Collection] the to collection
  # @param from_collection [Collection] the from collection
  # @param association_map [Array<{to_loc: loc, from_loc: loc}, ...>] optional
  #         if nil will assume one-to-one
  # @param transfer_vol [String] Optional else all
  def collection_to_collection_transfer_instructions(to_collection:,
                                                     from_collection:,
                                                     association_map: nil,
                                                     transfer_vol: nil)
    if transfer_vol.nil?
      amount_to_transfer = 'everything'
    else
        amount_to_transfer = {transfer_vol}.to_s
    end


    if association_map.nil?
      association_map = one_to_one_association_map(to_collection: to_collection,
                                              from_collection: from_collection)
    end

    from_rcx = []
    to_rcx = []

    association_map.each do |loc_hash|
      from_location = loc_hash[:from_loc]
      to_location = loc_hash[:to_loc]
      from_alpha_location = convert_coordinates_to_location(to_location)
      from_rcx.push(append_x_to_rcx(from_location, from_alpha_location))
      to_rcx.push(append_x_to_rcx(to_location, from_alpha_location))
    end

    show do
      title 'Transfer from one plate to another'
      note "Please transfer <b>#{amount_to_transfer}</b> from Plate
          (<b>ID:#{from_collection.id}</b>) to plate
          (<b>ID:#{to_collection.id}</b>) per tables below"
      separator
      note "Stock Plate (ID: <b>#{from_collection.id}</b>):"
      table highlight_collection_rcx(from_collection, from_rcx,
                                     check: false)
      note "Working Plate (ID: <b>#{to_collection}</b>):"
      table highlight_collection_rcx(to_collection, to_rcx,
                                     check: false)
    end
  end

    # (Verified)
    # Instructions to transfer items to wells of a collection
    #
    # @param to_collection [Collection] the plate that is getting the association
    # @param from_item [item] the item that is transferring the association
    # @param Association_map [Array<{to_loc: loc, from_loc: item}>] 
    #     Association map of where items are coming from.
    #     If nil will assume transferred to all wells.
    # @param transfer_vol [Integer] the volume transferred if applicable default
    #         nil if nil then will state unknown transfer vol
    def item_to_collection_transfer_instructions(to_collection:, association_map: nil,
      transfer_vol: nil)
      if transfer_vol.nil?
        amount_to_transfer = "everything"
      else
        amount_to_transfer = "#{transfer_vol}"
      end
      list_of_items = [to_collection]
      rcx_list = []
      association_map.each do |map|
        to_location = map[:to_loc]
        convert_location_to_coordinates(to_location) if to_location.is_a? String


        from_item = map[:from_loc]
        from_item = Item.find(from_item) unless from_item.is_a? Item
        list_of_items.push(from_item)

        rcx_list.push([to_location[0], to_location[1], from_item.id])
      end

      show do
        title "Get items for transfer"
        note 'Please get the following items'
        table create_location_table(list_of_items)
      end


      show do
        title 'Transfer from items to the plate'
        note "Please transfer <b>#{amount_to_transfer}</b> from the items 
              listed to Plate #{to_collection.id}"
        separator
        note "Plate (ID: <b>#{to_collection.id}</b>):"
        table highlight_collection_rcx(to_collection, rcx_list,
                                      check: true)
      end
    end

    # Verified
    # Instructions to transfer from wells in a collection to items
    #
    # @param to_collection [Collection] the plate that is getting the association
    # @param from_item [item] the item that is transferring the association
    # @param Association_map [Array<{to_loc: loc, from_loc: item}>] 
    #     If nil will assume transferred to all wells.
    # @param transfer_vol [Integer] the volume transferred if applicable default
    #   nil if nil then will state unknown transfer vol
    def collection_to_items_transfer_instructions(from_collection:,
                                                  association_map: nil,
                                                  transfer_vol: nil)
      if transfer_vol.nil?
        amount_to_transfer = "everything"
      else
        amount_to_transfer = "#{transfer_vol}"
      end
      list_of_items = [to_collection]
      rcx_list = []

      association_map.each do |map|
        from_location = map[:from_loc]

        if from_location.is_a? String
          convert_location_to_coordinates(from_location)
        end

        to_item = map[:to_loc]
        to_item = Item.find(to_item) unless to_item.is_a? Item
        list_of_items.push(to_item)

        rcx_list.push([from_location[0], from_location[1], to_item.id])
      end


      show do
        title "Get items for transfer"
        note 'Please get the following items'
        table create_location_table(list_of_items)
      end


      show do
        title 'Transfer from one plate to another'
        note "Please transfer <b>#{amount_to_transfer}</b> from Plate 
              #{from_collection.id} to the items listed"
        separator
        note "Plate (ID: <b>#{from_collection.id}</b>):"
        table highlight_collection_rcx(from_collection, rcx_list,
                                      check: true)
      end
    end

    # Creates an association map of items to a collection (verified)
    #
    # @param fv_array [Array<FieldValue or Items>] field values or items
    # @param collection [to_collection] the collection that things are in
    # @return [Array<{to_loc: location, from_loc: location}, ...]
    def make_item_to_collection_association_map(fv_array, collection:)
      association_map = []
      fv_array.each do |item|
        item = item.item if item.is_a? FieldValue
        unless item.is_a? Sample
          item = item.sample
        end

        to_location = collection.find(item)
        to_location.each do |loc|
          ProtocolError 'Wrong Loc format' unless loc.is_a? Array
          from_location = item.id
          unless loc.nil?
            association_map.push({to_loc: loc, from_loc: from_location})
          end
        end
      end
      association_map
    end


    # Tracks provenance and adds transfer vol association
    # for item to well transfers
    #
    #
    # @param to_collection [Collection] the plate that is getting the association
    # @param from_item [item] the item that is transferring the association
    # @param Association_map [Array<{to_loc: loc, from_loc: item},...>]
    #     If nil will assume transferred to all wells.
    #     Can take standard Array of Hashes as used in other methods in this
    #       library
    # @param transfer_vol [Integer] the volume transferred if applicable default
    #   nil if nil then will state unknown transfer vol
    def associate_items_to_wells(to_collection:, association_map: nil,
                                transfer_vol: nil)
      association_map.each do |map|
        to_loc = map[:to_loc]
        from_item = map[:from_loc]
        from_item = Item.find(from_item) unless from_item.is_a? Item

        to_part = to_collection.part(to_loc[0], to_loc[1])

        unless transfer_vol.nil?
          associate_transfer_vol(transfer_vol, VOL_TRANSFER, to_part: to_part,
                                                            from_part: from_item)
        end
        from_obj_to_obj_provenance(to_part, from_item)
      end
    end

    # Creates data association based on plate map for transfer
    # Additionally tracks provenance through items.
    #
    #
    # @param from_collection [Collection] the is transferring the association
    # @param to_item [item] the item that is getting_the association
    # @param Association_map [Array<Hash{to_loc: item, from_loc: [row, col]}, ...] 
    #      Association map of where items are coming from and going to.
    # @param transfer_vol [String] the volume transferred if applicable
    def associate_wells_to_item(from_collection:, association_map: nil,
                                transfer_vol: nil)
      association_map.each do |map|
        from_loc = map[:from_loc]
        if from_loc.is_a? String
          from_loc = convert_location_to_coordinates(from_loc)
        end

        from_part = from_collection.part(from_loc[0], from_loc[1])
        to_item = map[:to_loc]
        to_item = Item.find(to_item) unless to_item.is_a? Item

        unless transfer_vol.nil?
          associate_transfer_vol(transfer_vol, VOL_TRANSFER,
                                              to_part: to_item,
                                              from_part: from_part)
        end
        from_obj_to_obj_provenance(to_item, from_part)
      end
    end


    # Makes proper association_map between to_collection and from_collection
    #
    # @param to_collection [Collection] the collection that things are moving to
    # @param from_collection [Collection] the collection that things are coming from
    # @param samples [Array<{to_loc: loc, from_loc: loc}>] array of samples that
    #             exists in both collections
    # @param one_to_one [Boolean] if true then will make an exact one to one transfer
    #         else creates map based on "similar" samples
    def make_one_to_many_association_map(to_collection:, from_collection:, 
                                         samples: nil, one_to_one: false)
      if one_to_one
        return one_to_one_association_map(to_collection: to_collection, 
                                          from_collection: from_collection)
      end


      if samples.nil?
        samples = find_like_samples(to_collection, from_collection)
      end
      # Array<{to_loc: loc, from_loc: loc}

      association_map = []
      samples_with_no_location = []

      samples.each do |sample|
        to_loc = to_collection.find(sample)
        from_loc = from_collection.find(sample)
        # TODO: figure out how the associations will work if there are multiple
        # to and from locations (works partially may could use improvement)

        if to_loc.nil? || from_loc.nil?
          samples_with_no_location.push(sample)
        end

        if from_loc.length == 1
          to_loc.each do |t_loc|
            association_map.push({ to_loc: t_loc, from_loc: from_loc.first })
          end
        else
          from_loc.each do |from_loc|
            match = false
            to_loc.each do |to_loc|
              if to_loc[0] == from_loc[0] && to_loc[1] == from_loc[1]
                match = true
                association_map.push({ to_loc: to_loc, from_loc: from_loc })
              end
            end
            ProtocolError "AssociationMap was not properly created." unless match
            # TODO: Create a better error handle here 
            # (make it so it shows them the issue more explicitly)
          end
        end
        association_map
      end

      unless samples_with_no_location.length == 0
        cancel_plan = show do
          title 'Some Samples were not found'
          warning 'Some samples there were expected were 
                        not found in the given plates'
          note 'The samples that could not be found are listed below'
          select ['Cancel', 'Continue'], var: 'cancel',
                  label: 'Do you want to cancel the plan?', default: 1
          samples_with_no_location.each do |sample|
            note "#{sample.id}"
          end
        end

        # TODO: Fail softly/continue with samples that were found
        if cancel_plan[:'cancel'] == 'Cancel'
          raise 'User Canceled plan because many samples could not be found'
        else
          raise "This module doesn't currently support 
                                continuing with existing samples"
        end
      end

      association_map
    end

    # Creates a one to one association map
    #
    # @param to_collection [Collection] the to collection
    # @param from_collection [Collection] the from collection
    # @param samples [Array<{to_loc: loc, from_loc: loc}, ...>]
    def one_to_one_association_map(to_collection:, from_collection:)
      to_row_dem, to_col_dem = to_collection.dimensions
      from_row_dem, from_col_dem = from_collection.dimensions
      unless to_row_dem == from_row_dem && to_col_dem == from_col_dem
        ProtocolError "Collection Dimensions do not match"
      end

      association_map = []
      to_row_dem.times do |row|
        to_col_dem.times do |col|
          unless to_collection.part(row, col).nil? || 
                          from_collection.part(row, col).nil?
            loc = [row, col]
            association_map.push({ to_loc: loc, from_loc: loc })
          end
        end
      end
      association_map
    end


    # Creates Data Association between to_collection and from_collection
    #
    # @param to_collection [Collection] the to collection
    # @param from_collection [Collection] the from collection
    # @param Association_map [Array<Hash<from_loc: loc1, to_loc: loc2>]
    #             optional Association map else one_to_one
    # @param transfer_vol [Integer] the volume transferred else all
    def associate_plate_to_plate(to_collection:, from_collection:, 
                                 association_map: nil, transfer_vol: nil)
      # if there is no association map assume one_to_one
      if association_map.nil?
        association_map = one_to_one_association_map(
                                                to_collection: to_collection,
                                                from_collection: from_collection)
      end

      from_obj_to_obj_provenance(to_collection, from_collection)

      association_map.each do |loc_hash|
        to_loc = loc_hash[:to_loc]
        from_loc = loc_hash[:from_loc]

        to_loc = convert_location_to_coordinates(to_loc) if to_loc.is_a? String
        if from_loc.is_a? String
          from_loc = convert_location_to_coordinates(from_loc)
        end

        to_part = to_collection.part(to_loc[0], to_loc[1])
        from_part = from_collection.part(from_loc[0], from_loc[1])

        unless transfer_vol.nil?
        associate_transfer_vol(transfer_vol, VOL_TRANSFER, to_part: to_part,
                                                          from_part: from_part)
      end

      from_obj_to_obj_provenance(to_part, from_part)
    end
  end

  # Records the volume transferred
  #
  # @param vol the volume transferred
  # @param to_part: part that is being transferred to
  # @param from_part: part that is being transferred from
  def associate_transfer_vol(vol, key, to_part:, from_part:)
    vol_transfer_array = get_associated_data(to_part, key)
    vol_transfer_array = [] if vol_transfer_array.nil?
    vol_transfer_array.push([from_part.id, vol])
    associate_data(to_part, key, vol_transfer_array)
  end
end #end of CollectionManagement