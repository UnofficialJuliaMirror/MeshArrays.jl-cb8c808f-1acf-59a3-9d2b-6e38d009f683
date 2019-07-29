
## demo functions:

"""
demo1(gridChoice)

Demonstrate basic fucntions (arithmetic, exchange, GCMGridLoad, gradient, etc.). Example call:

```
isdir("GRID_LLC90") ? (D,Dexch,Darr,DD)=demo1("LLC90") : nothing
```
"""
function demo1(gridChoice)

    GCMGridSpec(gridChoice)

    D=read_bin(MeshArrays.grDir*"Depth.data",MeshArrays.ioPrec)

    1000+D
    D+1000
    D+D
    D-1000
    1000-D
    D-D
    1000*D
    D*1000
    D*D
    D/1000
    1000/D
    D/D

    Dexch=exchange(D,4)
    Darr=convert2array(D)
    DD=convert2array(Darr)

    GCMGridLoad()

    (dFLDdx, dFLDdy)=gradient(MeshArrays.YC)
    (dFLDdxEx,dFLDdyEx)=exchange(dFLDdx,dFLDdy,4)

    view(MeshArrays.hFacC,:,:,40)
    #show(fsize(MeshArrays.hFacC,1))
    #show(fsize(view(MeshArrays.hFacC,:,:,40),1))

    return (D,Dexch,Darr,DD)

end

##

"""
demo2()

Demonstrate higher level functions using smooth() and

```
isdir("GRID_LLC90") ? demo1("LLC90") : GCMGridOnes("cs",6,100)
(Rini,Rend,DXCsm,DYCsm)=demo2()
@time Rend=smooth(Rini,DXCsm,DYCsm)

include(joinpath(dirname(pathof(MeshArrays)),"gcmfaces_plot.jl"))
qwckplot(Rini)
qwckplot(Rend)
```

"""
function demo2()

    #Pre-requisite: either load predefined grid using `demo1` or call `GCMGridOnes`

    #initialize 2D field of random numbers
    tmp1=convert2gcmfaces(MeshArrays.XC);
    tmp1=randn(Float32,size(tmp1));
    Rini=convert2gcmfaces(tmp1);

    #apply land mask
    if ndims(MeshArrays.hFacC.f[1])>2
        tmp1=mask(view(MeshArrays.hFacC,:,:,1),NaN,0);
    else
        tmp1=mask(MeshArrays.hFacC,NaN,0);
    end
    msk=fill(1.,tmp1) + 0. *tmp1;
    Rini=msk*Rini;

    #specify smoothing length scales in x, y directions
    DXCsm=3*MeshArrays.DXC; DYCsm=3*MeshArrays.DYC;

    #apply smoother
    Rend=smooth(Rini,DXCsm,DYCsm);

    return (Rini,Rend,DXCsm,DYCsm)

end

"""
demo3()

Demonstrate computations of ocean meridional transports. Calling sequence:

```
!isdir("GRID_LLC90")||!isdir("nctiles_climatology") ? error("missing files") : nothing

GCMGridSpec("LLC90")
GCMGridLoad()

include(joinpath(dirname(pathof(MeshArrays)),"gcmfaces_nctiles.jl"))
fileName="nctiles_climatology/UVELMASS/UVELMASS"
U=read_nctiles(fileName,"UVELMASS");
fileName="nctiles_climatology/VVELMASS/VVELMASS"
V=read_nctiles(fileName,"VVELMASS");

(UV, LC, Tr)=demo3(U,V);

using Statistics
include(joinpath(dirname(pathof(MeshArrays)),"gcmfaces_plot.jl"))
qwckplot(UV["U"][:,:,1,1],"U component (note varying face orientations)")
qwckplot(UV["V"][:,:,1,1],"V component (note varying face orientations)")
plot(dropdims(mean(sum(Tr,dims=2),dims=3),dims=(2,3))/1e6,title="meridional transport")
```
"""
function demo3(U,V)

    LC=LatCircles(-89.0:89.0)

    U=mask(U,0.0)
    V=mask(V,0.0)

    UV=Dict("U"=>U,"V"=>V,"dimensions"=>["x","y","z","t"],"factors"=>["dxory","dz"])

    n=size(U)
    Tr=Array{Float64}(undef,length(LC),n[3],n[4])
    for i=1:length(LC)
        Tr[i,:,:]=TransportThrough(UV,LC[i])
    end

    return UV, LC, Tr

end

function TransportThrough(VectorField,IntegralPath)

    #Note: vertical intergration is not always wanted; left for user to do outside

    U=VectorField["U"]
    V=VectorField["V"]

    nd=ndims(U)
    #println("nd=$nd and d=$d")

    n=fill(1,4)
    tmp=size(U)
    n[1:nd].=tmp[1:nd]

    haskey(VectorField,"factors") ? f=VectorField["factors"] : f=Array{String,1}(undef,nd)
    haskey(VectorField,"dimensions") ? d=VectorField["dimensions"] : d=Array{String,1}(undef,nd)

    length(d)!=nd ? error("inconsistent specification of dims") : nothing

    trsp=Array{Float64}(undef,1,n[3],n[4])
    do_dz=sum(f.=="dz")
    do_dxory=sum(f.=="dxory")

    for i3=1:n[3]
        #method 1: quite slow
        #mskW=IntegralPath["mskW"]
        #do_dxory==1 ? mskW=mskW*MeshArrays.DYG : nothing
        #do_dz==1 ? mskW=MeshArrays.DRF[i3]*mskW : nothing
        #mskS=IntegralPath["mskS"]
        #do_dxory==1 ? mskS=mskS*MeshArrays.DXG : nothing
        #do_dz==1 ? mskS=MeshArrays.DRF[i3]*mskS : nothing
        #
        #method 2: less slow
        tabW=IntegralPath["tabW"]
        tabS=IntegralPath["tabS"]
        for i4=1:n[4]
            #method 1: quite slow
            #trsp[1,i3,i4]=sum(mskW*U[:,:,i3,i4])+sum(mskS*V[:,:,i3,i4])
            #
            #method 2: less slow
            trsp[1,i3,i4]=0.0
            for k=1:size(tabW,1)
                (a,i1,i2,w)=tabW[k,:]
                do_dxory==1 ? w=w*MeshArrays.DYG.f[a][i1,i2] : nothing
                do_dz==1 ? w=w*MeshArrays.DRF[i3] : nothing
                trsp[1,i3,i4]=trsp[1,i3,i4]+w*U.f[a][i1,i2,i3,i4]
            end
            for k=1:size(tabS,1)
                (a,i1,i2,w)=tabS[k,:]
                do_dxory==1 ? w=w*MeshArrays.DXG.f[a][i1,i2] : nothing
                do_dz==1 ? w=w*MeshArrays.DRF[i3] : nothing
                trsp[1,i3,i4]=trsp[1,i3,i4]+w*V.f[a][i1,i2,i3,i4]
            end
        end
    end

    return trsp
end

function LatCircles(LatValues)

    LatCircles=Array{Dict}(undef,length(LatValues))

    for j=1:length(LatValues)
        mskCint=1*(MeshArrays.YC .>= LatValues[j])
        mskC=similar(mskCint)
        mskW=similar(mskCint)
        mskS=similar(mskCint)

        mskCint=exchange(mskCint,1)

        for i=1:mskCint.nFaces
            tmp1=mskCint.f[i]
            # tracer mask:
            tmp2=tmp1[2:end-1,1:end-2]+tmp1[2:end-1,3:end]+
            tmp1[1:end-2,2:end-1]+tmp1[3:end,2:end-1]
            mskC.f[i]=1((tmp2.>0).&(tmp1[2:end-1,2:end-1].==0))
            # velocity masks:
            mskW.f[i]=tmp1[2:end-1,2:end-1] - tmp1[1:end-2,2:end-1]
            mskS.f[i]=tmp1[2:end-1,2:end-1] - tmp1[2:end-1,1:end-2]
        end

        tmp=vec(collect(mskC[:,1]))
        ind = findall(x -> x!=0, tmp)
        tabC=Array{Int,2}(undef,length(ind),4)
        for j=1:length(ind)
            tabC[j,1:3]=collect(fijind(mskC,ind[j]))
            tabC[j,4]=tmp[ind[j]]
        end

        tmp=vec(collect(mskW[:,1]))
        ind = findall(x -> x!=0, tmp)
        tabW=Array{Int,2}(undef,length(ind),5)
        for j=1:length(ind)
            tabW[j,1:3]=collect(fijind(mskW,ind[j]))
            tabW[j,4]=tmp[ind[j]]
            tabW[j,5]=ind[j]
        end

        tmp=vec(collect(mskS[:,1]))
        ind = findall(x -> x!=0, tmp)
        tabS=Array{Int,2}(undef,length(ind),5)
        for j=1:length(ind)
            tabS[j,1:3]=collect(fijind(mskS,ind[j]))
            tabS[j,4]=tmp[ind[j]]
            tabS[j,5]=ind[j]
        end

        LatCircles[j]=Dict("lat"=>LatValues[j],
        #"mskC"=>mskC,"mskW"=>mskW,"mskS"=>mskS,
        "tabC"=>tabC,"tabW"=>tabW,"tabS"=>tabS)
    end

    return LatCircles

end
