# Stacked predictions of Nigeria OCP site indices
# M. Walsh, January 2019 (2020 update)

# Required packages
# install.packages(c("devtools","caret","mgcv","MASS","randomForest","gbm","nnet","plyr","doParallel","dismo")), dependencies=T)
suppressPackageStartupMessages({
  require(devtools)
  require(caret)
  require(mgcv)
  require(MASS)
  require(randomForest)
  require(gbm)
  require(nnet)
  require(plyr)
  require(doParallel)
  require(dismo)
})

# Data setup --------------------------------------------------------------
# Run this first: https://github.com/mgwalsh/Geosurvey/blob/master/OCP_trial_data.R
# or run ...
# SourceURL <- "https://raw.githubusercontent.com/mgwalsh/blob/master/OCP_trial_data.R"
# source_url(SourceURL)
rm(list=setdiff(ls(), c("sidat","grids","glist"))) ## scrub extraneous objects in memory

# crop ROI extent
ext <- c(-1600250,-910500,362000,750000)
bb <- extent(ext)
grids <- crop(grids, bb)

# set calibration/validation set randomization seed
seed <- 12358
set.seed(seed)

# split data into calibration and validation sets
gsIndex <- createDataPartition(sidat$sic, p = 4/5, list = F, times = 1)
gs_cal <- sidat[ gsIndex,]
gs_val <- sidat[-gsIndex,]

# Trial calibration labels
labs <- c("sic") ## A = 'above average', B = below average site indices
lcal <- as.vector(t(gs_cal[labs]))

# raster calibration features
fcal <- gs_cal[,7:28,32:55]

# Spatial trend model <mgcv> -----------------------------------------------
# select x,y location grids
gf_cpv <- gs_cal[,29:31]

# start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# control setup
set.seed(1385321)
tc <- trainControl(method = "cv", classProbs = T, 
                   summaryFunction = twoClassSummary, allowParallel = T)

# model training
gm <- train(gf_cpv, lcal, 
             method = "gam",
             preProc = c("center","scale"), 
             family = "binomial",
             metric = "ROC",
             trControl = tc)

# model outputs & predictions
summary(gm)
gm.pred <- predict(grids, gm, type = "prob") ## spatial predictions
stopCluster(mc)
fname <- paste("./Results/", labs, "_gm.rds", sep = "")
saveRDS(gm, fname)

# Central place theory model <MASS> ---------------------------------------
# select central place covariates
gf_cpv <- gs_cal[,15:28]

# start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# control setup
set.seed(1385321)
tc <- trainControl(method = "cv", classProbs = T,
                   summaryFunction = twoClassSummary, allowParallel = T)

# model training
gl1 <- train(gf_cpv, lcal, 
             method = "glmStepAIC",
             family = "binomial",
             preProc = c("center","scale"), 
             trControl = tc,
             metric ="ROC")

# model outputs & predictions
summary(gl1)
print(gl1) ## ROC's accross cross-validation
gl1.pred <- predict(grids, gl1, type = "prob") ## spatial predictions
stopCluster(mc)
fname <- paste("./Results/", labs, "_gl1.rds", sep = "")
saveRDS(gl1, fname)

# GLM with all covariates <MASS> -------------------------------------------
# start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# control setup
set.seed(1385321)
tc <- trainControl(method = "cv", classProbs = T,
                   summaryFunction = twoClassSummary, allowParallel = T)

# model training
gl2 <- train(fcal, lcal, 
             method = "glmStepAIC",
             family = "binomial",
             preProc = c("center","scale"), 
             trControl = tc,
             metric ="ROC")

# model outputs & predictions
summary(gl2)
print(gl2) ## ROC's accross cross-validation
gl2.pred <- predict(grids, gl2, type = "prob") ## spatial predictions
stopCluster(mc)
fname <- paste("./Results/", labs, "_gl2.rds", sep = "")
saveRDS(gl2, fname)

# Random forest <randomForest> --------------------------------------------
# start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# control setup
set.seed(1385321)
tc <- trainControl(method = "cv", classProbs = T,
                   summaryFunction = twoClassSummary, allowParallel = T)
tg <- expand.grid(mtry = seq(1,5, by=1)) ## model tuning steps

# model training
rf <- train(fcal, lcal,
            preProc = c("center","scale"),
            method = "rf",
            ntree = 501,
            metric = "ROC",
            tuneGrid = tg,
            trControl = tc)

# model outputs & predictions
print(rf) ## ROC's accross tuning parameters
rf.pred <- predict(grids, rf, type = "prob") ## spatial predictions
stopCluster(mc)
fname <- paste("./Results/", labs, "_rf.rds", sep = "")
saveRDS(rf, fname)

# Generalized boosting <gbm> ----------------------------------------------
# start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# control setup
set.seed(1385321)
tc <- trainControl(method = "cv", classProbs = T, summaryFunction = twoClassSummary,
                   allowParallel = T)

## for initial <gbm> tuning guidelines see @ https://stats.stackexchange.com/questions/25748/what-are-some-useful-guidelines-for-gbm-parameters
tg <- expand.grid(interaction.depth = seq(2,5, by=1), shrinkage = 0.01, n.trees = seq(101,501, by=50),
                  n.minobsinnode = 50) ## model tuning steps

# model training
gb <- train(fcal, lcal, 
            method = "gbm", 
            preProc = c("center", "scale"),
            trControl = tc,
            tuneGrid = tg,
            metric = "ROC")

# model outputs & predictions
print(gb) ## ROC's accross tuning parameters
gb.pred <- predict(grids, gb, type = "prob") ## spatial predictions
stopCluster(mc)
fname <- paste("./Results/", labs, "_gb.rds", sep = "")
saveRDS(gb, fname)

# Neural network <nnet> ---------------------------------------------------
# start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# control setup
set.seed(1385321)
tc <- trainControl(method = "cv", classProbs = T,
                   summaryFunction = twoClassSummary, allowParallel = T)
tg <- expand.grid(size = seq(2,10, by=2), decay = c(0.001, 0.01, 0.1)) ## model tuning steps

# model training
nn <- train(fcal, lcal, 
            method = "nnet",
            preProc = c("center","scale"), 
            tuneGrid = tg,
            trControl = tc,
            metric ="ROC")

# model outputs & predictions
print(nn) ## ROC's accross tuning parameters
nn.pred <- predict(grids, nn, type = "prob") ## spatial predictions
stopCluster(mc)
fname <- paste("./Results/", labs, "_nn.rds", sep = "")
saveRDS(nn, fname)

# Model stacking setup ----------------------------------------------------
preds <- stack(gm.pred, gl1.pred, gl2.pred, rf.pred, gb.pred, nn.pred)
names(preds) <- c("gm","gl1","gl2","rf","gb","nn")
plot(preds, axes = F)

# extract model predictions
coordinates(gs_val) <- ~x+y
projection(gs_val) <- projection(preds)
gspred <- extract(preds, gs_val)
gspred <- as.data.frame(cbind(gs_val, gspred))

# stacking model validation labels and features
gs_val <- as.data.frame(gs_val)
lval <- as.vector(t(gs_val[labs]))
fval <- gspred[,56:61] ## subset validation features

# Model stacking ----------------------------------------------------------
# start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# control setup
set.seed(1385321)
tc <- trainControl(method = "cv", classProbs = T, 
                   summaryFunction = twoClassSummary, allowParallel = T)

# model training
st <- train(fval, lval,
            method = "glm",
            family = "binomial",
            metric = "ROC",
            trControl = tc)

# model outputs & predictions
summary(st)
print(st)
st.pred <- predict(preds, st, type = "prob") ## spatial predictions
plot(st.pred, axes = F)
stopCluster(mc)
fname <- paste("./Results/", labs, "_st.rds", sep = "")
saveRDS(st, fname)

# Receiver-operator characteristics ---------------------------------------
cp_pre <- predict(st, fval, type="prob")
cp_val <- cbind(lval, cp_pre)
cpp <- subset(cp_val, cp_val=="A", select=c(A))
cpa <- subset(cp_val, cp_val=="B", select=c(A))
cp_eval <- evaluate(p=cpp[,1], a=cpa[,1]) ## calculate ROC's on test set
plot(cp_eval, 'ROC') ## plot ROC curve

# Generate feature mask ---------------------------------------------------
t <- threshold(cp_eval) ## calculate thresholds based on ROC
r <- matrix(c(0, t[,1], 0, t[,1], 1, 1), ncol=3, byrow = T) ## set threshold value <kappa>
mask <- reclassify(st.pred, r) ## reclassify stacked predictions
plot(mask, axes=F)

# Write prediction grids --------------------------------------------------
gspreds <- stack(preds, 1-st.pred, mask)
names(gspreds) <- c("gm","gl1","gl2","rf","gb","nn","st","mk")
fname <- paste("./Results/","OCP_", labs, "_preds_2020.tif", sep = "")
writeRaster(gspreds, filename=fname, datatype="FLT4S", options="INTERLEAVE=BAND", overwrite=T)

# Write output data frame -------------------------------------------------
coordinates(sidat) <- ~x+y
projection(sidat) <- projection(grids)
gspre <- extract(gspreds, sidat)
gsout <- as.data.frame(cbind(sidat, gspre))
gsout$mzone <- ifelse(gsout$mk == 1, "A", "B")
confusionMatrix(data = gsout$mzone, reference = gsout$sic, positive = "A")
fname <- paste("./Results/","OCP_", labs, "_out.csv", sep = "")
write.csv(gsout, fname, row.names = F)

