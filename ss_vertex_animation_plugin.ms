macroScript VertexAnimation category: "Vertex Animation Tool"
buttontext:"Vertex Animation Tool" tooltip:"Vertex Animation Tool"
(
	ResumeEditing()
	escapeEnable = true

	global default_Morph_FloaterOpen=True
	global targetMorphUV=2

	fn reinitRolloutSize = 
	(
		mR=if default_Morph_FloaterOpen == true then 340 else 28
		kR=if default_SelectionSequenceRolloutOpen == true then 88 else 28
		Morph_Floater.Size=[300,(mR+kR)]

	)

	fn CheckUnitsSetup = 
	(
		if (units.SystemType!=#Centimeters)  
		then 
		(
			messagebox "Please change your file's unit type to centimeters.\r\rGo to ''Customize'' in the main tool bar, ''Units Setup'' then press the \r''System Unit Setup'' button and finally choose ''Centimeters'' from the dropdown list."
			false
		) 
		else 
		(
			true
		)
	)

	fn CheckMesh mesh = 
	(
		isvalidnode mesh and superclassof mesh == GeometryClass 
	)

	rollout TexMorphRollout "Vertex Animation Tool: Export as Texture" (
		on TexMorphRollout rolledUp state do 
		(
			default_Morph_FloaterOpen=state 
			reinitRolloutSize()			
		)

		global originalMesh -- 平滑后的起始模型
		global copyBaseMesh 
		global numberofVerts -- 原始模型的顶点数目
		global originalMeshVertPositions=#() -- 平滑后的起始模型存储的顶点位置
		global MorphTargetArray
		global Morph_Floater
		global internalArrayOfStaticBaseMeshes=#() -- 选中的模型们的一维数组
		global vertexUVPosition=#()
		global MorphNormalArray=#()
		global MorphVertOffsetArray=#()
		global MorphTargetProgressPercentage = 0.0
		global masterMorphArray=#() -- 二维数组，第一层为选中的模型，第二层为那个模型对应时间范围内的所有snapshot
		global noMeshesArray=#(" No meshes processed" as string)

		checkbox captureAbsolutePositions "Capture Absolute Positions" tooltip:"This is an advanced feature. Use this to capture the verts' absolute positions. This data, when used with the morph target material functions, requires that world position be subtracted from the material function's world position offset output and the actor position to be added back to the result before being used in the world position offset node. This feature may reduce your morph target's effective range but will allow users to generate additional advanced effects."
		group "Animated Meshes"
        (
            spinner spinnerAnimationRangeStart "Anim Start" type:#integer range:[0,1000000,animationRange.start]
            spinner spinnerAnimationRangeEnd "Anim End" type:#integer range:[0,1000000,animationRange.end]
			spinner spinnerAnimationRate "Frame step Skip" type:#integer range:[0,1000000,0]
			dropdownlist ddlTextureCoordinate "Texture Coordinate:" items:#("2","3","4","5","6","7","8") tooltip:"选择第二套UV来放顶点动画的顶点位置"

			button CreateVertexAnimation "Create Vertex Animation"
			
			edittext vertCountText "Vertex Count" text:"..." readOnly:true
			edittext frameCountText "Frame Count" text:"..." readOnly:true
			edittext offsetText "Offset" text:"..." readOnly:true
			edittext scaleText "Scale" text:"..." readOnly:true
		)	

		on ddlTextureCoordinate selected i do 
		(
			targetMorphUV=ddlTextureCoordinate.items[i] as integer 
		)

		button help "help"
		on help pressed do
        (
            S = #()
            HelpString = ""
            append S "第一步：输入顶点动画开始的位置。"
            append S "第二步：输入顶点动画结束的位置。"
            append S "第三步：输入顶点动画需要跳过的位置。"
            append S "第四步：选择一个供顶点动画贴图sample的UV空间,默认使用第二套UV"
			append S "第五步：点击生成顶点动画按钮，选择导出路径。"
			
            for i in S do HelpString += i + "\n"
            messageBox HelpString
		)
		
		-- functions
		fn MsgBreak = 
		(
			format "*** % ***\n" (getCurrentException())
			messagebox ("An error has occured. Please send the this text to Jonathan.lindquist@epicgames.com \r\r''" + getCurrentException() + "''")
		)

		fn UpdateProgAmount i myArrayCount = 
		(
			MorphTargetProgressPercentage=((i as float/myArrayCount as float)*100.0)
			progressUpdate MorphTargetProgressPercentage   
			if MorphTargetProgressPercentage == 100.0 do progressEnd()
			if getProgressCancel() == true do 
			(
				progressEnd()
			)
		)

		fn ReInitVariables = 
		(
			masterMorphArray=#()
			MorphVertOffsetArray=#()
			originalMesh=undefined
			numberofVerts=0
			internalArrayOfStaticBaseMeshes=#()
			MorphTargetProgressPercentage=0.0
			originalMeshVertPositions=#()
			MorphNormalArray=#()
			tempMorphArray=#()		
		)

		-- 给每一帧都创建snapshot
		fn MakeSnapshotsReturnArray modelToSnap= 
		(
			progressStart "Creating Morph Targets" 
			FrameArray=#()

			-- 用户在UI里定义的参数
			NumberOfFrames = floor (spinnerAnimationRangeEnd.value-spinnerAnimationRangeStart.value) --/(spinnerAnimationRate.value+1)
			frameCountText.text = NumberOfFrames as string

			for i=0 to NumberOfFrames by (spinnerAnimationRate.value+1) do 
			(
				newtime = spinnerAnimationRangeStart.value+i 
				newCopy = at time newtime snapshot modelToSnap
				meshop.unifyNormals newCopy #{1..newCopy.numfaces}
				
				--!convertto newCopy editable_poly
				append FrameArray newCopy
				UpdateProgAmount i NumberOfFrames
			)
			progressEnd()
			FrameArray
		)

		-- 合并多个mesh
		fn AttachMeshes mesh1 mesh2= 
		(
			if classof mesh1 == editable_poly then mesh1.attach mesh2 mesh1
				else attach mesh1 mesh2 
		)

		-- 保存模型和对应的snapshot
		fn MakeAndMergeSnapShots arrayOfModels = 
		(
			if arrayOfModels.count > 0 do 
			(
				for i in arrayOfModels do 
				(
					-- MakeSnapshotsReturnArray会返回对应模型在连续帧内的快照
					if CheckMesh i do append masterMorphArray (MakeSnapshotsReturnArray i)
				)
				-- consolidate multiple objects into one object so that the morph texture can be shared
				-- 下标从1开始！
				masterMorphArray1Count=masterMorphArray[1].count
				If masterMorphArray.count > 1 do 
				(
					for i=2 to masterMorphArray.count do 
					(
						--master arrays each item is a group
						for framecount=1 to masterMorphArray1Count do 
						( 
							-- Loop through each of the objects stored from each frame... then combine them with their associated paired meshes. the first mesh being the father of the others
							currentMasterObject=masterMorphArray[1][framecount]
							AttachMeshes currentMasterObject masterMorphArray[i][framecount]
						)
					)
				)
				-- 全部合并到mesh1
				masterMorphArray = masterMorphArray[1]
			)
		)

		-- store an array to querry instead of the object
		fn StoreOriginalMeshVertPositions = 
		(
			--清空位置数组，定义在全局
			originalMeshVertPositions= #()

			if classof originalMesh.baseobject == Editable_Poly then 
			( 
				for i=1 to numberofVerts do 
				(
					append originalMeshVertPositions (in coordsys world polyop.getVert originalMesh i)
				)
			) 
			else 
			(
				for i=1 to numberofVerts do 
				(
					append originalMeshVertPositions (in coordsys world getVert originalMesh i)
				)
			)
			originalMeshVertPositions
		)

		fn SmoothCopy myMesh = 
		(
			/********** Duplicate the Mesh **********/
			originalName=myMesh.name
			originalMesh=at time 0 snapshot myMesh
			originalMesh.name=originalName+"_MorphUV"+(targetMorphUV as string)+"_MorphExport"

			s=smooth()
			s.smoothingBits = 1
			addmodifier originalMesh s

			/********** Duplicate the Mesh **********/
			numberofVerts = getNumVerts originalMesh

			print originalMesh;
			print numberofVerts;
			vertCountText.text=numberofVerts as string

			StoreOriginalMeshVertPositions () 
		)

		fn FixUVNames polyToFix = 
		(
			for i = 1 to (polyop.getNumMaps polyToFix) do (ChannelInfo.NameChannel polyToFix 3 i ("UVChannel_" + i as string))
		)

		-- arrange the uvs
		function PackVertUVs myMesh =
		(
			progressStart "Packing the game meshes UVs" 
			convertTo myMesh Editable_Poly

			for i=1 to (numberofVerts) do 
			(
				-- offset=1.0/(numberofVerts*2) -- find have a sample ratio
				-- currentPosition=(((i as float)-0.5)/numberofVerts)
				currentPosition = i-1; -- 尝试直接存原始数据，shader里减少乘法计算
				polyop.setVertColor myMesh targetMorphUV i [currentPosition*255.0,128.0,0]
				append vertexUVPosition CurrentPosition
				
				UpdateProgAmount i numberofVerts
			)

			FixUVNames myMesh
			progressEnd()
		)

		--得到snapshot中对应顶点的法线
		fn getTheVertexNormal processObject vertexIndex = 
		( 
			normal = [0.0,0.0,0.0] 
			if classof processObject.baseobject == Editable_Poly then 
			(
				vertexPolygons = polyOp.getFacesUsingVert processObject vertexIndex
				for i in vertexPolygons do 
				(
					normal+=in coordsys world polyOp.getFaceNormal processObject i
				)
			) 
			else 
			(
				normal= getNormal processObject vertexIndex
			)
			normal=normalize normal 
			normal 
		)

		--得到snapshot中对应顶点的位置
		fn getVertPos model index= 
		(
			pos=[0,0,0]
			if classof model.baseobject == editable_poly then 
			(
				pos=in coordsys world polyop.getVert model index
			) 
			else 
			(
				pos=in coordsys world getVert model index
			)
			pos
		)

		-- 编码主体
		fn PopulateMorphTargetArrays =
		(
			progressStart "Creating the Morph Targets" 
			masterCount=masterMorphArray.count -- 帧数

			global maxValue = 0.0
			global minValue = 0.0
			global min2max = 0.0

			-- 遍历每帧每顶点
			for i=1 to masterCount do 
			(
				global CurrentMorphTargetNormalArray=#()
				global currentMorphVertexOffsetArray=#()

				currentMorphTarget=masterMorphArray[i]					

				-- 更新进度条
				MorphTargetProgressPercentage=UpdateProgAmount i masterCount

				-- 由于smooth modifier，FBX导出时应选择平滑组
				for j=1 to numberofVerts do 
				(
					-- normal的编码方式
					-- 把rgb都编到0--1
					oldnormal=((((normalize (getTheVertexNormal currentMorphTarget j))*[1.0,-1.0,1.0])+1.0)*0.5)*255.0
					append CurrentMorphTargetNormalArray oldnormal

					originalVertPos=originalMeshVertPositions[j]
					currentModelVertPos=getVertPos currentMorphTarget j

					if (captureAbsolutePositions.checked) 
					then 
					(
						-- 该选项下，直接记录绝对位置而不是offset
						currentOffset=currentModelVertPos
					)
					else 
					(
						currentOffset=(currentModelVertPos-originalVertPos)
					)

					minValue = amin minValue currentOffset.x
					minValue = amin minValue currentOffset.y
					minValue = amin minValue currentOffset.z

					maxValue = amax maxValue currentOffset.x
					maxValue = amax maxValue currentOffset.y
					maxValue = amax maxValue currentOffset.z

					-- 如何编码offset
					-- currentOffset=[currentOffset[1],-1.0*currentOffset[2],currentOffset[3]]
					-- currentOffset*=255.0
					currentOffset=[currentOffset[1],currentOffset[2],currentOffset[3]]

					append currentMorphVertexOffsetArray currentOffset
				)
				append MorphVertOffsetArray currentMorphVertexOffsetArray
				append MorphNormalArray CurrentMorphTargetNormalArray
			)

			format "minValue = %\n" minValue
			format "maxValue = %\n" maxValue
			min2max = maxValue - minValue
			offsetValue = minValue
			scaleValue = min2max

			offsetText.text = offsetValue as string
			scaleText.text = scaleValue as string
		)

		fn RemoveMeshes = 
		(
			if isvalidnode masterMorphArray[1] and masterMorphArray.count > 0 do 
			(
				delete masterMorphArray
				masterMorphArray=#()
			)
		)

		-- 输出贴图，UE方案，强行改成hdr（exr不支持导入）
		fn RenderOutTheTextures = 
		(	
			fopenexr.SetCompression 0
			fopenexr.setLayerOutputType 0 1 -- set layer 0  main layer to RGBA, RGB = 1
			fopenexr.setLayerOutputFormat 0 1 --0 32 sets main layer to float 16 via 1. other options are 0 float 32, 2 int 32 
			global TextureName = getSaveFileName types:"hdr (*.hdr)|*.hdr"
			if TextureName == undefined then 
			(
				messagebox "please select a file location"
			)
			else
			(
				uvString="_UV"+((targetMorphUV-1) as string)
				TextureNameNormal= replace TextureName (findString TextureName ".hdr") 4 (uvString+"_Normals.BMP")
				TextureNameOffset= replace TextureName (findString TextureName ".hdr") 4 (uvString+".hdr")

				local FinalPosTexture = bitmap numberofVerts (MorphVertOffsetArray.count) filename:TextureNameOffset hdr:true;
				local FinalNormalTexture = bitmap numberofVerts (MorphVertOffsetArray.count) filename:TextureNameNormal hdr:true gamma:1.0;--TextureName ;linear:true gamma:#default

				for i=0 to (MorphVertOffsetArray.count-1) do 
				(
					setPixels FinalPosTexture [0, i] MorphVertOffsetArray[(i+1)]
					setPixels FinalNormalTexture [0, i] MorphNormalArray[(i+1)]
				)
				save FinalPosTexture gamma:1.0
				close FinalPosTexture
				
				save FinalNormalTexture gamma:1.0
				close FinalNormalTexture
			)
		)

		-- 输出remap贴图结果
		fn RenderOutTheRemapTextures = 
		(
			-- save offsets as texture
			local filePath = getSaveFileName types:"BMP (*.BMP)|*.BMP"
			if filePath == undefined then 
			(
				messagebox "please select a file location"
			) 
			else
			(
				uvString="_UV"+((targetMorphUV-1) as string)
				TextureNameNormal= replace filePath (findString filePath ".BMP") 4 (uvString+"_normals.BMP")
				TextureNameOffset= replace filePath (findString filePath ".BMP") 4 (uvString+"_offsets.BMP")

				local FinalPosTexture = bitmap numberofVerts (MorphVertOffsetArray.count) filename:TextureNameOffset hdr:false gamma:1.0;
				local FinalNormalTexture = bitmap numberofVerts (MorphVertOffsetArray.count) filename:TextureNameNormal hdr:false gamma:1.0;

				for i=0 to (MorphVertOffsetArray.count-1) do 
				(
					local colors=#()

					for w=1 to numberofVerts do
					(
						local offset=MorphVertOffsetArray[(i+1)][w]
						local x = (offset.x - minValue) / min2max * 255.0
						local y = (offset.y - minValue) / min2max * 255.0
						local z = (offset.z - minValue) / min2max * 255.0
						local w = 1.0
						append colors (color x y z w)
					)

					setPixels FinalPosTexture [0, i] colors
					setPixels FinalNormalTexture [0, i] MorphNormalArray[(i+1)]
				)

				save FinalPosTexture gamma:1.0
				close FinalPosTexture
				
				save FinalNormalTexture gamma:1.0
				close FinalNormalTexture
			)
		)

		-- press create vertex animation button
		on CreateVertexAnimation pressed do
		(
			if CheckUnitsSetup()==true do 
			(
				SuspendEditing()
				try
				with redraw off
				(
					ReInitVariables()
					
					-- 把选中的模型压入数组internalArrayOfStaticBaseMeshes
					for i in selection do if CheckMesh i do append internalArrayOfStaticBaseMeshes i

					geoConversionModelFailNamelist=#()

					-- 遍历所有选中的需要处理的模型，找出有问题的
					for i in internalArrayOfStaticBaseMeshes do 
					(
						modelCopy=convertto (snapshot i) editable_poly
						if ((getnumverts i)!= (getnumverts modelCopy)) do append geoConversionModelFailNamelist i.name
						delete modelCopy
					)

					-- 如果有问题模型，就不烘焙
					if geoConversionModelFailNamelist.count > 0 then  
					(
						finalWarningString="在转换为可编辑的多边形对象后，以下网格顶点转换计数发生了变化，因此无法烘焙动画。\n"
						for i in geoConversionModelFailNamelist do append finalWarningString  ("\r - "+i)
						messagebox finalWarningString
					)
					else
					(
						if internalArrayOfStaticBaseMeshes.count > 0 then
						(
							-- 根据每帧生成snapshot，并且合并了多个mesh
							MakeAndMergeSnapShots internalArrayOfStaticBaseMeshes

							-- 第0帧是基准模型，也就是之后会导出的静态模型
							-- 记录它平滑后的信息
							SmoothCopy masterMorphArray[1]

							-- 生成平滑后静态初始模型的uv
							PackVertUVs originalMesh 

							-- 编码位置和法线
							PopulateMorphTargetArrays ()

							RemoveMeshes()

							-- 输出贴图
							-- RenderOutTheTextures() 		
							RenderOutTheRemapTextures()

							-- fixUVNames originalMesh 
							-- convertto originalMesh editable_mesh
							clearSelection()
							select originalMesh
						)
						else
						(
							messageBox "没有选中任何有效物体！"
						)
					)  
				)
				catch
				(
					MsgBreak ()
					ResumeEditing()
				)
			)
			ResumeEditing()
		)		
	)

	if Morph_Floater != undefined then CloseRolloutFloater Morph_Floater
	global Morph_Floater = newRolloutFloater "" 300 400 
	addRollout TexMorphRollout Morph_Floater
)

macros.run "Vertex Animation Tool" "VertexAnimation"