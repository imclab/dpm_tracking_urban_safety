function detected_root_filters = get_detected_filters(pyra, model, bs, trees)
    %
    % Return values
    %   detected_root_filters(num_detections).f -- one root filter per detection
    %
    % Arguments
    %   pyra        Feature pyramid
    %   model       Object model
    %   bs          Detection boxes
    %   trees       Detection derivation trees from gdetect.m

    maxsize = inf;
    maxnum = inf;
    count = 0;
    if ~isempty(bs)
      [count, detected_root_filters] = writefeatures(pyra, model, trees, maxsize, maxnum);
      % truncate boxes
      bs(count+1:end,:) = [];
    end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% writes feature vectors for the detections in trees
function [count, detected_root_filters] = writefeatures(pyra, model, trees, maxsize, maxnum)
% location/scale features
    loc_f = loc_feat(model, pyra.num_levels);

    % Precompute which blocks we need to write features for
    % We can skip writing features for a block if
    % the block is not learned AND the weights are all zero
    write_block = false(model.numblocks, 1);
    for i = 1:model.numblocks
      all_zero = all(model.blocks(i).w == 0);
      write_block(i) = ~(model.blocks(i).learn == 0 && all_zero == 0);
    end

    detected_root_filters = [];
    count = 0;
    for d = 1:min(maxnum, length(trees))
      t = tree_mat_to_struct(trees{d});
      ex = [];
      %ex.key = [dataid; t(1).l; t(1).x; t(1).y];
      ex.blocks(model.numblocks).f = [];
      ex.loss = t(1).loss;

      for j = 1:length(t)
        sym = t(j).symbol;
        if model.symbols(sym).type == 'T'
          fi = model.symbols(sym).filter;
          bl = model.filters(fi).blocklabel;
          if write_block(bl)
            ex = addfilterfeat(model, ex,             ...
                               t(j).x, t(j).y,        ...
                               pyra.padx, pyra.pady,  ...
                               t(j).ds, fi,           ...
                               pyra.feat{t(j).l});
          end
          if (t(j).ds == 0) %is this is a root filter?
            detected_root_filters(d).f = reshape(ex.blocks(bl).f, model.blocks(bl).shape); %got the reshape idea from model_get_block()
          end
        else
          ruleind = t(j).rule_index;
          if model.rules{sym}(ruleind).type == 'D'
            bl = model.rules{sym}(ruleind).def.blocklabel;
            if write_block(bl)
              dx = t(j).dx;
              dy = t(j).dy;
              def = [-(dx^2); -dx; -(dy^2); -dy];
              if model.rules{sym}(ruleind).def.flip
                def(2) = -def(2);
              end
              if isempty(ex.blocks(bl).f)
                ex.blocks(bl).f = def;
              else
                ex.blocks(bl).f = ex.blocks(bl).f + def;
              end
            end
          end
          % offset
          bl = model.rules{sym}(ruleind).offset.blocklabel;
          if write_block(bl)
            if isempty(ex.blocks(bl).f)
              ex.blocks(bl).f = model.features.bias;
            else
              ex.blocks(bl).f = ex.blocks(bl).f + model.features.bias;
            end
          end
          % location/scale features
          bl = model.rules{sym}(ruleind).loc.blocklabel;
          if write_block(bl)
            l = t(j).l;
            if isempty(ex.blocks(bl).f)
              ex.blocks(bl).f = loc_f(:,l);
            else
              ex.blocks(bl).f = ex.blocks(bl).f + loc_f(:,l);
            end
          end
        end
      end
      count = count + 1;
    end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% stores the filter feature vector in the example ex
function ex = addfilterfeat(model, ex, x, y, padx, pady, ds, fi, feat)
    % model object model
    % ex    example that is being extracted from the feature pyramid
    % x, y  location of filter in feat (with virtual padding)
    % padx  number of cols of padding
    % pady  number of rows of padding
    % ds    number of 2x scalings (0 => root level, 1 => first part level, ...)
    % fi    filter index
    % feat  padded feature map

    fsz = model.filters(fi).size;
    % remove virtual padding
    fy = y - pady*(2^ds-1);
    fx = x - padx*(2^ds-1);
    f = feat(fy:fy+fsz(1)-1, fx:fx+fsz(2)-1, :);

    % flipped filter
    if model.filters(fi).flip
      %f = flipfeat(f); %Forrest -- remove flipping 
    end

    % accumulate features
    bl = model.filters(fi).blocklabel;
    if isempty(ex.blocks(bl).f)
      ex.blocks(bl).f = f(:);
    else
      ex.blocks(bl).f = ex.blocks(bl).f + f(:);
    end

