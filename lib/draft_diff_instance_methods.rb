module DraftPunk
  module Model
    module DraftDiffInstanceMethods

      # Return the differences between the live and draft object.
      #
      # If include_associations is true, it will return the diff for all child associations, recursively until it gets
      # to the bottom of your draft tree. This only works for associations which have the approved_version_id column
      #
      # @param include_associations [Boolean] include diff for child objects, recursive (possibly down to grandchildren and beyond)
      # @param include_all_attributes [Boolean] return all attributes in the results, including those which have not changed
      # @return (Hash)
      def draft_diff(include_associations: false, parent_object_fk: nil, include_all_attributes: false)
        get_object_changes(self, draft, include_associations, parent_object_fk, include_all_attributes)
      end

    protected #################################################################
      def current_approvable_attributes
        attribs = {}
        attributes.each do |k,v|
          attribs[k] = v if k.in?(diff_relevant_attributes)
        end
      end    

    private ####################################################################

      def get_object_changes(approved_obj, draft_obj, include_associations, parent_object_fk, include_all_attributes)
        diff = {}
        approved_attribs = approved_obj ? approved_obj.current_approvable_attributes : {}
        draft_attribs    = draft_obj    ? draft_obj.current_approvable_attributes    : {}
        diff_relevant_attributes(parent_object_fk).each do |attrib|
          live  = approved_attribs[attrib]
          draft = draft_attribs[attrib]
          diff[attrib] = {live: live, draft: draft} if include_all_attributes || live != draft 
        end
        diff.merge!(draft_status: :deleted) if parent_object_fk.present? && draft_attribs[parent_object_fk].nil?
        diff.merge!(associations_diff(include_all_attributes)) if include_associations
        diff[:draft_status] = diff_status(diff, parent_object_fk) unless diff.has_key?(:draft_status)
        diff[:class_info]   = {table_name: approved_obj.class.table_name, class_name: approved_obj.class.name}
        diff
      end

      def associations_diff(include_all_attributes)
        diff = {}
        self.class.draft_target_associations.each do |assoc|
          next unless association_tracks_approved_version?(assoc)
          diff[assoc] = []
          draft_versions = [editable_version.send(assoc)].flatten.compact
          approved_versions = [get_approved_version.send(assoc)].flatten.compact
          foreign_key = self.class.reflect_on_association(assoc).foreign_key

          approved_versions.each do |approved|
            obj_diff = approved.draft_diff(include_associations: true, parent_object_fk: foreign_key, include_all_attributes: include_all_attributes)
            obj_diff.merge(draft_status: :deleted) unless draft_versions.find{|obj| obj.approved_version_id == approved.id }
            diff[assoc] << obj_diff if (include_all_attributes || obj_diff[:draft_status] != :unchanged)
          end
          draft_versions.select{|obj| obj.approved_version_id.nil? }.each do |draft|
            diff[assoc] << draft.draft_diff(include_associations: true, include_all_attributes: include_all_attributes).merge(draft_status: :added)
          end
        end
        diff.select{|k,v| v.present? || include_all_attributes}
      end

      def diff_status(diff, parent_object_fk)
        return if diff.has_key?(:status)
        diff.each do |attrib, value|
          if value.is_a?(Hash) && !attrib.in?([parent_object_fk.to_s, 'id'])
            return :changed unless value[:live] == value[:draft]
          end
        end
        :unchanged
      end

      def diff_relevant_attributes(parent_object_fk=nil)
        (usable_approvable_attributes + ['id'] - ['updated_at', 'approved_version_id', parent_object_fk]).map(&:to_s).uniq.compact
      end

    end
  end
end