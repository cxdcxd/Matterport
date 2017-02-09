require 'image'
require 'cutorch'
require 'cunn'
require 'cudnn'
require 'optim'

-- Custom files
require 'model'
require 'util'
-- require 'qtwidget' -- for visualizing images

opt_string = [[
    -h,--help                                       print help
    -s,--save               (default "logs")        subdirectory to save logs
    -b,--batchSize          (default 64)            batch size
    -r,--learningRate       (default 0.01)          learning rate
    --learningRateDecay     (default 1e-7)          learning rate decay
    --weigthDecay           (default 0.0005)        weight decay
    -m,--momentum           (default 0.9)           mementum
    --epoch_step            (default 20)            epoch step
    -g,--gpu_index          (default 0)             GPU index (start from 0)
    --max_epoch             (default 200)           maximum number of epochs
    --train_data            (default "data/modelnet40_60x/train_data.txt")     txt file containing train h5 filenames
    --test_data             (default "data/modelnet40_60x/test_data.txt")      txt file containing test h5 filenames
]]

opt = lapp(opt_string)

-- print help or chosen options
if opt.help == true then
    print('Usage: th train.lua')
    print('Options:')
    print(opt_string)
    os.exit()
else
    print(opt)
end

-- set gpu
cutorch.setDevice(opt.gpu_index+1)

-- Set RNG seed
math.randomseed(os.time())

-- Load model and criterion
model,criterion = getModel()
model:zeroGradParameters()
parameters, gradParameters = model:getParameters()
print(model)

-- Construct window for visualizing training examples
-- visWindow = qtwidget.newwindow(1792,672)

--[[
-- load training and testing files
train_files = getDataFiles(opt.train_data)
test_files = getDataFiles(opt.test_data)
print(train_files)
print(test_files)
--]]

-- config for SGD solver
optimState = {
    learningRate = opt.learningRate,
    weightDecay = opt.weigthDecay,
    momentum = opt.momentum,
    learningRateDecay = opt.learningRateDecay,
}

-- config logging
testLogger = optim.Logger(paths.concat(opt.save, 'test.log'))
testLogger:setNames{'% mean class accuracy (train set)', '% mean class accuracy (test set)'}

------------------------------------
-- Training routine
--
function train()
    model:training()
    epoch = epoch or 1 -- if epoch not defined, assign it as 1
    print('epoch ' .. epoch)
    if epoch % opt.epoch_step == 0 then optimState.learningRate = optimState.learningRate/2 end

    -- shuffle train files
    local train_file_indices = torch.randperm(#train_files)

    local tic = torch.tic()
    for fn = 1, #train_files do
        local currentDataMatch,currentDataAnchor,currentDataNegMatch = loadDataFile(train_files[train_file_indices[fn]])

        local filesize = (#current_data)[1]
        local indices = torch.randperm(filesize):long():split(opt.batchSize)
        -- remove last mini-batch so that all the batches have equal size
        indices[#indices] = nil 

        for t, v in ipairs(indices) do 
            -- print progress bar :D
            xlua.progress(t, #indices)

            local inputs = { currentDataMatch:index(1,v):cuda(), currentDataAnchor:index(1,v):cuda(), currentDataNegMatch:index(1,v):cuda() }       

            -- a function that takes single input and return f(x) and df/dx
            local feval = function(x)
                if x ~= parameters then parameters:copy(x) end
                gradParameters:zero()
                
	            -- Forward and backward pass
	            local output = model:forward(inputs)
	            local loss = criterion:forward(output)
	            print('Training iteration '..trainIter..': '..loss)
	            local dLoss = criterion:backward(output)
	            model:backward(inputs,dLoss)
	            return loss,gradParameters
            end
            
            -- use SGD optimizer: parameters as input to feval will be updated
            optim.sgd(feval, parameters, optimState)
        end
    end
    --TODO PRINT TRAIN LOSS/ACCURACY
    epoch = epoch + 1
end

-------------------------------------
-- Test routine
--

function test()
    model:evaluate()
    for fn = 1, #test_files do
        local currentDataMatch,currentDataAnchor,currentDataNegMatch = loadDataFile(train_files[train_file_indices[fn]])

        local filesize = (#current_data)[1]
        local indices = torch.randperm(filesize):long():split(opt.batchSize)
        for t, v in ipairs(indices) do
            local inputs = { currentDataMatch:index(1,v):cuda(), currentDataAnchor:index(1,v):cuda(), currentDataNegMatch:index(1,v):cuda() }       
            local outputs = model:forward(inputs)
            local loss = criterion:forward(output)
        end
    end
    --[[ --TODO PRINT TEST LOSS/ACCURACY 
    if testLogger then
        paths.mkdir(opt.save)
        testLogger:add{train_acc, confusion.totalValid * 100}
        testLogger:style{'-','-'}
    end
    --]]

    -- save model every 10 epochs
    if epoch % 10 == 0 then
      local filename = paths.concat(opt.save, 'model_' ..tostring(epoch) .. '.net')
      print('==> saving model to '..filename)
      torch.save(filename, model:clearState())
    end 
end

-----------------------------------------
-- Start training
--
for i = 1,opt.max_epoch do
    train()
    test()
end

--[[
for trainIter = 1,1000 do

	-- Create a mini-batch of training examples
	for i = 1,8 do 

		-- Get training triplet of anchor patch, matching patch, and non-matching patch
		local matchPatch,anchorPatch,nonMatchPath = getTrainingExampleTriplet()

		-- Reshape data for input to network
		matchPatch = matchPatch:reshape(1,3,224,224);
		anchorPatch = anchorPatch:reshape(1,3,224,224);
		nonMatchPath = nonMatchPath:reshape(1,3,224,224);
		if i == 1 then
			input = {matchPatch,anchorPatch,nonMatchPath}
			-- mosaic = anchorPatch:reshape(3,224,224):cat(matchPatch:reshape(3,224,224),2):cat(nonMatchPath:reshape(3,224,224),2)
		else
			input[1] = input[1]:cat(matchPatch,1)
			input[2] = input[2]:cat(anchorPatch,1)
			input[3] = input[3]:cat(nonMatchPath,1)
			-- mosaic = mosaic:cat(anchorPatch:reshape(3,224,224):cat(matchPatch:reshape(3,224,224),2):cat(nonMatchPath:reshape(3,224,224),2),3)
		end
	end

	-- Convert input to GPU memory
	input[1] = input[1]:cuda()
	input[2] = input[2]:cuda()
	input[3] = input[3]:cuda()

	-- Visualize training examples (console command: qlua -lenv train.lua)
	-- image.display{image=mosaic,offscreen=false,win=visWindow}

	params,gradParams = model:getParameters()
	local feval = function(x)

	    -- Update model parameters
	    if x ~= params then
	        params:copy(x) 
	    end

	    -- Reset gradients
	    gradParams:zero() 

	    -- Forward and backward pass
	    local output = model:forward(input)
	    local loss = criterion:forward(output)
	    print('Training iteration '..trainIter..': '..loss)
	    local dLoss = criterion:backward(output)
	    model:backward(input,dLoss)
	    return loss,gradParams
	end

	-- Update model parameters (SGD)
	optim.sgd(feval,params,optimState)

	-- Save training snapshot of model
	if trainIter%100 == 0 then
		local filename = paths.concat("snapshots","snapshot_"..trainIter..".net")
		os.execute('mkdir -p '..sys.dirname(filename))
		torch.save(filename, model:clearState()) 
	end
end
--]]
