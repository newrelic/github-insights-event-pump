module PayloadUtils

  # Traverse the hash via '/' separated keys, returning nil if any part is missing
  def find(hash, path)
    return hash if path.nil?
    segment, remainder = path.split('/', 2)
    if hash.include? segment
      find hash[segment], remainder
    else
      nil
    end
  end

  def merge_property(attrs, root, key, *paths)
    paths = [key] if paths.empty?
    for path in paths do
      val = find(root, path)
      if val
        if block_given?
          val = yield val.to_s[0..2046]
          attrs[key] = val if val
        else
          attrs[key] = val.is_a?(String) ? val[0..2046] : val
        end
        break
      end
    end
  end

end
