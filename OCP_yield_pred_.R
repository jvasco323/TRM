# Stacked predictions of Nigeria OCP site indices
# M. Walsh, January 2019

# Required packages
# install.packages(c("devtools","caret","MASS","randomForest","gbm","nnet","plyr","doParallel","dismo")), dependencies=T)
suppressPackageStartupMessages({
  require(devtools)
  require(caret)
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

# set calibration/validation set randomization seed
seed <- 12358
set.seed(seed)

# split data into calibration and validation sets
gsIndex <- createDataPartition(sidat$sic, p = 4/5, list = F, times = 1)
gs_cal <- sidat[ gsIndex,]
gs_val <- sidat[-gsIndex,]

# GeoSurvey calibration labels
cp_cal <- gs_cal$sic

# raster calibration features
gf_cal <- gs_cal[,7:49]

# Central place theory model <glm> -----------------------------------------
# select central place covariates
gf_cpv <- gs_cal[,16:26]

# start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# control setup
set.seed(1385321)
tc <- trainControl(method = "cv", classProbs = T,
                   summaryFunction = twoClassSummary, allowParallel = T)

# model training
gl1 <- train(gf_cpv, cp_cal, 
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

# GLM with all covariates -------------------------------------------------
# start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# control setup
set.seed(1385321)
tc <- trainControl(method = "cv", classProbs = T,
                   summaryFunction = twoClassSummary, allowParallel = T)

# model training
gl2 <- train(gf_cal, cp_cal, 
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
rf <- train(gf_cal, cp_cal,
            preProc = c("center","scale"),
            method = "rf",
            ntree = 501,
            metric = "ROC",
            tuneGrid = tg,
            trControl = tc)

# model outputs & predictions
print(rf) ## ROC's accross tuning parameters
plot(varImp(rf)) ## relative variable importance
rf.pred <- predict(grids, rf, type = "prob") ## spatial predictions

stopCluster(mc)

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
gb <- train(gf_cal, cp_cal, 
            method = "gbm", 
            preProc = c("center", "scale"),
            trControl = tc,
            tuneGrid = tg,
            metric = "ROC")

# model outputs & predictions
print(gb) ## ROC's accross tuning parameters
plot(varImp(gb)) ## relative variable importance
gb.pred <- predict(grids, gb, type = "prob") ## spatial predictions

stopCluster(mc)

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
nn <- train(gf_cal, cp_cal, 
            method = "nnet",
            preProc = c("center","scale"), 
            tuneGrid = tg,
            trControl = tc,
            metric ="ROC")

# model outputs & predictions
print(nn) ## ROC's accross tuning parameters
plot(varImp(nn)) ## relative variable importance
nn.pred <- predict(grids, nn, type = "prob") ## spatial predictions

stopCluster(mc)

# Model stacking setup ----------------------------------------------------
preds <- stack(gl1.pred, gl2.pred, rf.pred, gb.pred, nn.pred)
names(preds) <- c("gl1","gl2","rf", "gb","nn")
plot(preds, axes = F)

# extract model predictions
coordinates(gs_val) <- ~x+y
projection(gs_val) <- projection(preds)
gspred <- extract(preds, gs_val)
gspred <- as.data.frame(cbind(gs_val, gspred))

# stacking model validation labels and features
cp_val <- gspred$sic
gf_val <- gspred[,50:54] ## subset validation features

# Model stacking ----------------------------------------------------------
# start doParallel to parallelize model fitting
mc <- makeCluster(detectCores())
registerDoParallel(mc)

# control setup
set.seed(1385321)
tc <- trainControl(method = "cv", classProbs = T, 
                   summaryFunction = twoClassSummary, allowParallel = T)

# model training
st <- train(gf_val, cp_val,
            method = "glm",
            family = "binomial",
            metric = "ROC",
            trControl = tc)

# model outputs & predictions
print(st)
plot(varImp(st))
st.pred <- predict(preds, st, type = "prob") ## spatial predictions
plot(st.pred, axes = F)

stopCluster(mc)

# Receiver-operator characteristics ---------------------------------------
cp_pre <- predict(st, gf_val, type="prob")
cp_val <- cbind(cp_val, cp_pre)
cpa <- subset(cp_val, cp_val=="A", select=c(A))
cpb <- subset(cp_val, cp_val=="B", select=c(B))
cp_eval <- evaluate(p=cpa[,1], a=cpb[,1]) ## calculate ROC's on test set
plot(cp_eval, 'ROC') ## plot ROC curve

# Generate feature mask ---------------------------------------------------
t <- threshold(cp_eval) ## calculate thresholds based on ROC
r <- matrix(c(0, t[,1], 0, t[,1], 1, 1), ncol=3, byrow = T) ## set threshold value <kappa>
mask <- reclassify(st.pred, r) ## reclassify stacked predictions
plot(mask, axes=F)

# Write prediction grids --------------------------------------------------
gspreds <- stack(preds, st.pred, mask)
names(gspreds) <- c("gl1","gl2","rf","gb","nn","st","mk")
writeRaster(gspreds, filename="./Results/NG__OCP_sic_preds.tif", datatype="FLT4S", options="INTERLEAVE=BAND", overwrite=T)

# Write output data frame -------------------------------------------------
coordinates(sidat) <- ~x+y
projection(sidat) <- projection(grids)
gspre <- extract(gspreds, sidat)
gsout <- as.data.frame(cbind(sidat, gspre))
gsout$mzone <- ifelse(gsout$mk == 1, "A", "B")
confusionMatrix(data = gsout$mzone, reference = gsout$sic, positive = "A")
write.csv(gsout, "./Results/OCP_sic_out.csv", row.names = F)

# Prediction map widget ---------------------------------------------------
pred <- st.pred ## GeoSurvey ensemble probability
pal <- colorBin("Greens", domain = 0:1) ## set color palette
w <- leaflet() %>% 
  setView(lng = mean(sidat$lon), lat = mean(sidat$lat), zoom = 6) %>%
  addProviderTiles(providers$OpenStreetMap.Mapnik) %>%
  addRasterImage(pred, colors = pal, opacity = 0.6, maxBytes=6000000) %>%
  addLegend(pal = pal, values = values(pred), title = "Site index prob.")
w ## plot widget 
saveWidget(w, 'NG_OCP_sic.html', selfcontained = T)