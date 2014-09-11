#if Tp == double
#pragma OPENCL EXTENSION cl_khr_fp64 : enable
#endif

#define NEAREST core_nearest1
#define LINEAR core_linear1

#if CPLX
#define set(a, b) a = b
#define set_scalar(a, b) do {                   \
        a.x = b;                                \
        a.y = 0;                                \
    } while(0)

Ty mul(Ty a, Tp b) { a.x = a.x * b; a.y = a.y * b; return a; }
Ty div(Ty a, Tp b) { a.x = a.x / b; a.y = a.y / b; return a; }

#else

#define set(a, b) a = b
#define set_scalar(a, b) a = b
#define mul(a, b) ((a) * (b))
#define div(a, b) ((a) / (b))

#endif

///////////////////////////////////////////////////////////////////////////
// nearest-neighbor resampling
///////////////////////////////////////////////////////////////////////////
void core_nearest1(const dim_type idx, const dim_type idy, const dim_type idz, const dim_type idw,
                   __global       Ty *d_out, const KParam out,
                   __global const Ty *d_in,  const KParam in,
                   __global const Tp *d_pos, const KParam pos,
                   const float offGrid)
{
    const dim_type omId = idw * out.strides[3] + idz * out.strides[2]
                        + idy * out.strides[1] + idx;
    const dim_type pmId = idx;

    const Tp pVal = d_pos[pmId];
    if (pVal < 0 || in.dims[0] < pVal+1) {
        set_scalar(d_out[omId], offGrid);
        return;
    }

    dim_type ioff = idw * in.strides[3] + idz * in.strides[2] + idy * in.strides[1];
    const dim_type imId = round(pVal) + ioff;

    Ty y;
    set(y, d_in[imId]);
    set(d_out[omId], y);
}

///////////////////////////////////////////////////////////////////////////
// linear resampling
///////////////////////////////////////////////////////////////////////////
void core_linear1(const dim_type idx, const dim_type idy, const dim_type idz, const dim_type idw,
                   __global       Ty *d_out, const KParam out,
                   __global const Ty *d_in,  const KParam in,
                   __global const Tp *d_pos, const KParam pos,
                   const float offGrid)
{
    const dim_type omId = idw * out.strides[3] + idz * out.strides[2]
                        + idy * out.strides[1] + idx;
    const dim_type pmId = idx;

    const Tp pVal = d_pos[pmId];
    if (pVal < 0 || in.dims[0] < pVal+1) {
        set_scalar(d_out[omId], offGrid);
        return;
    }

    const Tp grid_x = floor(pVal);  // nearest grid
    const Tp off_x = pVal - grid_x; // fractional offset

    dim_type ioff = idw * in.strides[3] + idz * in.strides[2] + idy * in.strides[1] + grid_x;

    // Check if pVal and pVal + 1 are both valid indices
    bool cond = (pVal < in.dims[0] - 1);
    Ty zero; set_scalar(zero, 0);

    // Compute Left and Right Weighted Values
    Ty yl; set(yl, mul(d_in[ioff] , (1 - off_x)));
    Ty yr; set(yr, cond ? mul(d_in[ioff + 1], off_x) : zero);
    Ty yo = yl + yr;

    // Compute Weight used
    Tp wt = cond ? 1 : (1 - off_x);

    // Write final value
    set(d_out[omId], div(yo, wt));
}

////////////////////////////////////////////////////////////////////////////////////
// Wrapper Kernel
////////////////////////////////////////////////////////////////////////////////////
__kernel
void approx1_kernel(__global       Ty *d_out, const KParam out,
                    __global const Ty *d_in,  const KParam in,
                    __global const Tp *d_pos, const KParam pos,
                    const float offGrid, const dim_type blocksMatX)
{
    const dim_type idw = get_group_id(1) / out.dims[2];
    const dim_type idz = get_group_id(1)  - idw * out.dims[2];

    const dim_type idy = get_group_id(0) / blocksMatX;
    const dim_type blockIdx_x = get_group_id(0) - idy * blocksMatX;
    const dim_type idx = get_local_id(0) + blockIdx_x * get_local_size(0);

    if(idx >= out.dims[0] ||
       idy >= out.dims[1] ||
       idz >= out.dims[2] ||
       idw >= out.dims[3])
        return;

    INTERP(idx, idy, idz, idw, d_out, out, d_in + in.offset, in, d_pos + pos.offset, pos, offGrid);
}
